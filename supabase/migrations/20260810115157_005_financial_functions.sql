/*
# Financial + referral + dashboard functions

1. Functions
- `create_deposit(p_amount, p_method)` — user creates a pending deposit. Does NOT change
  balance. Returns the deposit row.
- `approve_deposit(p_deposit_id)` — admin-only. Idempotent: if already approved, no-op.
  Atomically inserts a `deposit` ledger transaction (unique reference), increments
  available_balance and total_deposited. Rejects if deposit not pending.
- `reject_deposit(p_deposit_id, p_note)` — admin-only. Sets status rejected.
- `request_withdrawal(p_amount, p_method, p_destination)` — user. Locks profile FOR UPDATE,
  validates min/max from app_settings, checks sufficient available_balance and cooldown,
  atomically reserves funds (available_balance -= amount, pending_balance += amount),
  inserts a `withdrawal` ledger transaction (negative, pending), creates withdrawal row.
- `approve_withdrawal(p_withdrawal_id)` — admin-only. Locks withdrawal, idempotent. Moves
  reserved amount: pending_balance -= amount, total_withdrawn += amount. Ledger tx completed.
- `reject_withdrawal(p_withdrawal_id, p_note)` — admin-only. Refunds reserved amount
  atomically: available_balance += amount, pending_balance -= amount. Creates a
  `withdrawal_refund` ledger transaction. Status rejected.
- `qualify_referral(p_referred_id)` — checks app_settings referral_qualification and, if
  met, marks referral qualified and credits referrer via `referral_reward` ledger tx.
  Called after PTC claim and task approval.
- `get_dashboard()` — returns aggregated stats for the authenticated user's dashboard.

2. Security
- All SECURITY DEFINER, search_path = public, REVOKE anon, GRANT authenticated.
- Admin functions check is_admin() using auth.uid().
- request_withdrawal uses SELECT FOR UPDATE on the profile to prevent double-spending.

3. Notes
- All money numeric(18,8). Unique `reference` columns provide idempotency.
*/

-- ---------- create_deposit ----------
CREATE OR REPLACE FUNCTION create_deposit(p_amount numeric, p_method text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  INSERT INTO deposits (user_id, amount, payment_method, status)
    VALUES (auth.uid(), p_amount, COALESCE(p_method, 'manual'), 'pending')
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'deposit_id', v_id, 'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION create_deposit(numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION create_deposit(numeric, text) TO authenticated;

-- ---------- approve_deposit ----------
CREATE OR REPLACE FUNCTION approve_deposit(p_deposit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deposit deposits%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_deposit FROM deposits WHERE id = p_deposit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deposit not found'; END IF;
  IF v_deposit.status = 'approved' THEN RETURN jsonb_build_object('ok', true, 'already_approved', true); END IF;
  IF v_deposit.status != 'pending' THEN RAISE EXCEPTION 'Deposit is not pending (status: %)', v_deposit.status; END IF;

  v_ref := 'deposit:' || v_deposit.id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (v_deposit.user_id, 'deposit', v_deposit.amount, 'deposit', v_deposit.id, v_ref, 'Deposit approved', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NOT NULL THEN
    UPDATE profiles
      SET available_balance = available_balance + v_deposit.amount,
          total_deposited = total_deposited + v_deposit.amount
      WHERE id = v_deposit.user_id;
  END IF;

  UPDATE deposits SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_deposit_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'approve_deposit', 'deposit', p_deposit_id::text,
      jsonb_build_object('amount', v_deposit.amount, 'user_id', v_deposit.user_id));

  RETURN jsonb_build_object('ok', true, 'transaction_id', v_tx_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION approve_deposit(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION approve_deposit(uuid) TO authenticated;

-- ---------- reject_deposit ----------
CREATE OR REPLACE FUNCTION reject_deposit(p_deposit_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deposit deposits%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_deposit FROM deposits WHERE id = p_deposit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deposit not found'; END IF;
  IF v_deposit.status = 'rejected' THEN RETURN jsonb_build_object('ok', true, 'already_rejected', true); END IF;
  IF v_deposit.status != 'pending' THEN RAISE EXCEPTION 'Deposit is not pending'; END IF;

  UPDATE deposits SET status = 'rejected', admin_note = COALESCE(p_note, ''), reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_deposit_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'reject_deposit', 'deposit', p_deposit_id::text,
      jsonb_build_object('note', p_note));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION reject_deposit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION reject_deposit(uuid, text) TO authenticated;

-- ---------- request_withdrawal ----------
CREATE OR REPLACE FUNCTION request_withdrawal(p_amount numeric, p_method text, p_destination text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_settings app_settings%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_wd_id uuid;
  v_last_withdrawal timestamptz;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_settings FROM app_settings WHERE id = 1;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF p_amount < v_settings.min_withdrawal THEN RAISE EXCEPTION 'Minimum withdrawal is %', v_settings.min_withdrawal; END IF;
  IF p_amount > v_settings.max_withdrawal THEN RAISE EXCEPTION 'Maximum withdrawal is %', v_settings.max_withdrawal; END IF;
  IF p_amount > v_profile.available_balance THEN RAISE EXCEPTION 'Insufficient available balance'; END IF;
  IF COALESCE(p_destination, '') = '' THEN RAISE EXCEPTION 'Destination is required'; END IF;

  -- cooldown check
  SELECT max(created_at) INTO v_last_withdrawal FROM withdrawals WHERE user_id = auth.uid() AND status = 'pending';
  IF v_last_withdrawal IS NOT NULL AND now() - v_last_withdrawal < (v_settings.withdrawal_cooldown_minutes || ' minutes')::interval THEN
    RAISE EXCEPTION 'Please wait before requesting another withdrawal';
  END IF;

  -- Reserve funds
  UPDATE profiles
    SET available_balance = available_balance - p_amount,
        pending_balance = pending_balance + p_amount
    WHERE id = auth.uid();

  INSERT INTO withdrawals (user_id, amount, withdrawal_method, destination, status)
    VALUES (auth.uid(), p_amount, COALESCE(p_method, 'manual'), p_destination, 'pending')
    RETURNING id INTO v_wd_id;

  v_ref := 'withdrawal:' || v_wd_id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'withdrawal', -p_amount, 'withdrawal', v_wd_id, v_ref, 'Withdrawal requested (reserved)', 'pending');

  RETURN jsonb_build_object('ok', true, 'withdrawal_id', v_wd_id, 'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION request_withdrawal(numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION request_withdrawal(numeric, text, text) TO authenticated;

-- ---------- approve_withdrawal ----------
CREATE OR REPLACE FUNCTION approve_withdrawal(p_withdrawal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_wd withdrawals%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_wd FROM withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal not found'; END IF;
  IF v_wd.status = 'paid' THEN RETURN jsonb_build_object('ok', true, 'already_paid', true); END IF;
  IF v_wd.status != 'pending' THEN RAISE EXCEPTION 'Withdrawal is not pending'; END IF;

  -- Move reserved -> withdrawn
  UPDATE profiles
    SET pending_balance = pending_balance - v_wd.amount,
        total_withdrawn = total_withdrawn + v_wd.amount
    WHERE id = v_wd.user_id;

  UPDATE transactions SET status = 'completed', description = 'Withdrawal paid'
    WHERE reference = 'withdrawal:' || v_wd.id::text;

  UPDATE withdrawals SET status = 'paid', reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_withdrawal_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'approve_withdrawal', 'withdrawal', p_withdrawal_id::text,
      jsonb_build_object('amount', v_wd.amount, 'user_id', v_wd.user_id));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION approve_withdrawal(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION approve_withdrawal(uuid) TO authenticated;

-- ---------- reject_withdrawal ----------
CREATE OR REPLACE FUNCTION reject_withdrawal(p_withdrawal_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_wd withdrawals%ROWTYPE;
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_wd FROM withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal not found'; END IF;
  IF v_wd.status = 'rejected' THEN RETURN jsonb_build_object('ok', true, 'already_rejected', true); END IF;
  IF v_wd.status != 'pending' THEN RAISE EXCEPTION 'Withdrawal is not pending'; END IF;

  -- Refund reserved funds
  UPDATE profiles
    SET available_balance = available_balance + v_wd.amount,
        pending_balance = pending_balance - v_wd.amount
    WHERE id = v_wd.user_id;

  UPDATE transactions SET status = 'reversed', description = 'Withdrawal rejected (refunded)'
    WHERE reference = 'withdrawal:' || v_wd.id::text;

  v_ref := 'withdrawal_refund:' || v_wd.id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (v_wd.user_id, 'withdrawal_refund', v_wd.amount, 'withdrawal', v_wd.id, v_ref, 'Withdrawal refund', 'completed')
    ON CONFLICT (reference) DO NOTHING;

  UPDATE withdrawals SET status = 'rejected', admin_note = COALESCE(p_note, ''), reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_withdrawal_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'reject_withdrawal', 'withdrawal', p_withdrawal_id::text,
      jsonb_build_object('note', p_note));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION reject_withdrawal(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION reject_withdrawal(uuid, text) TO authenticated;
