/*
 * User-to-User XC Transfer System
 *
 * Allows authenticated users to transfer XC balance to another registered user.
 * Recipient resolved by username or email (case-insensitive).
 *
 * Architecture:
 * - xc_transfers table stores transfer metadata (sender, recipient, amount, status, reference).
 * - transactions ledger gets two rows per transfer: debit sender (type 'xc_transfer_sent'),
 *   credit recipient (type 'xc_transfer_received'), both currency='XC', sharing a unique
 *   reference prefix for idempotency.
 * - SECURITY DEFINER RPC `xc_transfer(p_recipient_query, p_amount, p_client_reference)` performs
 *   the atomic debit/credit with FOR UPDATE row locking.
 * - `xc_lookup_recipient(p_query)` resolves a recipient by username/email without exposing
 *   sensitive fields.
 * - `list_xc_transfers` returns the calling user's transfer history.
 * - `admin_list_xc_transfers` returns all transfers for admins.
 * - total_earned is NOT touched — transfers are balance movements, not earnings.
 * - USD/USDT balances are NOT touched.
 *
 * RLS:
 * - xc_transfers: SELECT own rows (sender_id = auth.uid() OR recipient_id = auth.uid()).
 *   No direct INSERT/UPDATE/DELETE — all writes via SECURITY DEFINER functions.
 */

-- =====================================================
-- 1. Extend transactions.type CHECK to include transfer + conversion types
-- =====================================================

ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check;

ALTER TABLE transactions
  ADD CONSTRAINT transactions_type_check CHECK (type IN (
    'ptc_reward','task_reward','referral_reward','deposit','withdrawal',
    'withdrawal_refund','adjustment','ad_transfer','ad_spend','ad_refund',
    'offer_reward','offer_reversal','xc_conversion',
    'xc_transfer_sent','xc_transfer_received'
  ));

-- =====================================================
-- 2. xc_transfers table
-- =====================================================

CREATE TABLE IF NOT EXISTS xc_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL,
  sender_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount numeric(18,8) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','failed','reversed')),
  client_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS xc_transfers_sender_idx ON xc_transfers (sender_id);
CREATE INDEX IF NOT EXISTS xc_transfers_recipient_idx ON xc_transfers (recipient_id);
CREATE INDEX IF NOT EXISTS xc_transfers_created_at_idx ON xc_transfers (created_at DESC);
CREATE INDEX IF NOT EXISTS xc_transfers_reference_idx ON xc_transfers (reference);

ALTER TABLE xc_transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "xc_transfers_select_own" ON xc_transfers;
CREATE POLICY "xc_transfers_select_own" ON xc_transfers FOR SELECT
  TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

-- =====================================================
-- 3. xc_lookup_recipient — resolve recipient by username or email
-- =====================================================

CREATE OR REPLACE FUNCTION xc_lookup_recipient(p_query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_self_id uuid;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_query IS NULL OR btrim(p_query) = '' THEN
    RAISE EXCEPTION 'Please enter a username or email';
  END IF;

  -- Case-insensitive lookup by username OR email
  SELECT * INTO v_profile FROM profiles
    WHERE lower(username) = lower(btrim(p_query))
       OR lower(email) = lower(btrim(p_query))
    LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  IF v_profile.id = v_self_id THEN
    RAISE EXCEPTION 'You cannot transfer XC to yourself';
  END IF;

  IF v_profile.status != 'active' THEN
    RAISE EXCEPTION 'Recipient account is not active';
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'id', v_profile.id,
    'username', v_profile.username,
    'full_name', v_profile.full_name,
    'avatar_url', v_profile.avatar_url
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION xc_lookup_recipient(text) FROM anon;
GRANT EXECUTE ON FUNCTION xc_lookup_recipient(text) TO authenticated;

-- =====================================================
-- 4. xc_transfer — atomic user-to-user XC transfer
-- =====================================================

CREATE OR REPLACE FUNCTION xc_transfer(
  p_recipient_query text,
  p_amount numeric,
  p_client_reference text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender profiles%ROWTYPE;
  v_recipient profiles%ROWTYPE;
  v_amount numeric(18,8);
  v_ref text;
  v_transfer_id uuid;
  v_tx_id uuid;
  v_existing xc_transfers%ROWTYPE;
BEGIN
  -- Authenticate
  SELECT * INTO v_sender FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_sender.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  -- Validate amount
  IF p_amount IS NULL THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  v_amount := round(p_amount::numeric, 8);
  IF v_amount IS NULL OR v_amount != v_amount THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF v_amount <= 0 THEN RAISE EXCEPTION 'Amount must be greater than zero'; END IF;
  IF v_amount < 0.01 THEN RAISE EXCEPTION 'Minimum transfer is 0.01 XC'; END IF;
  IF v_amount > v_sender.xc_balance THEN RAISE EXCEPTION 'Insufficient XC balance'; END IF;

  -- Resolve recipient
  IF p_recipient_query IS NULL OR btrim(p_recipient_query) = '' THEN
    RAISE EXCEPTION 'Please enter a recipient username or email';
  END IF;

  SELECT * INTO v_recipient FROM profiles
    WHERE lower(username) = lower(btrim(p_recipient_query))
       OR lower(email) = lower(btrim(p_recipient_query))
    LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
  IF v_recipient.id = v_sender.id THEN RAISE EXCEPTION 'You cannot transfer XC to yourself'; END IF;
  IF v_recipient.status != 'active' THEN RAISE EXCEPTION 'Recipient account is not active'; END IF;

  -- Build unique reference. Use client_reference for idempotency if provided.
  IF p_client_reference IS NOT NULL AND btrim(p_client_reference) != '' THEN
    v_ref := 'xctx:' || auth.uid()::text || ':' || btrim(p_client_reference);
    -- Check if this client_reference already processed
    SELECT * INTO v_existing FROM xc_transfers WHERE reference = v_ref;
    IF FOUND THEN
      -- Idempotent return of the original transfer
      RETURN jsonb_build_object(
        'ok', true,
        'duplicate', true,
        'transfer_id', v_existing.id,
        'reference', v_existing.reference,
        'amount', v_existing.amount,
        'recipient_username', v_recipient.username,
        'sender_xc_balance', v_sender.xc_balance
      );
    END IF;
  ELSE
    v_ref := 'xctx:' || auth.uid()::text || ':' || v_recipient.id::text || ':' || extract(epoch from now())::bigint::text || ':' || v_amount::text;
  END IF;

  -- Insert transfer record (idempotent on reference)
  INSERT INTO xc_transfers (reference, sender_id, recipient_id, amount, status, client_reference, completed_at)
    VALUES (v_ref, v_sender.id, v_recipient.id, v_amount, 'completed', p_client_reference, now())
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_transfer_id;

  IF v_transfer_id IS NULL THEN
    -- Race: another concurrent request inserted the same reference
    SELECT * INTO v_existing FROM xc_transfers WHERE reference = v_ref;
    RETURN jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'transfer_id', v_existing.id,
      'reference', v_existing.reference,
      'amount', v_existing.amount,
      'recipient_username', v_recipient.username,
      'sender_xc_balance', v_sender.xc_balance
    );
  END IF;

  -- Debit sender
  INSERT INTO transactions (
    user_id, type, amount, currency, usd_equivalent,
    reference_type, reference_id, reference, description, status
  ) VALUES (
    v_sender.id, 'xc_transfer_sent', -v_amount, 'XC', NULL,
    'xc_transfer', v_transfer_id, v_ref || ':send',
    'XC transfer to @' || v_recipient.username, 'completed'
  )
  ON CONFLICT (reference) DO NOTHING
  RETURNING id INTO v_tx_id;

  -- Credit recipient
  INSERT INTO transactions (
    user_id, type, amount, currency, usd_equivalent,
    reference_type, reference_id, reference, description, status
  ) VALUES (
    v_recipient.id, 'xc_transfer_received', v_amount, 'XC', NULL,
    'xc_transfer', v_transfer_id, v_ref || ':recv',
    'XC transfer from @' || v_sender.username, 'completed'
  )
  ON CONFLICT (reference) DO NOTHING;

  -- Move balances (NOT total_earned — transfers are not earnings)
  UPDATE profiles
    SET xc_balance = xc_balance - v_amount
    WHERE id = v_sender.id;

  UPDATE profiles
    SET xc_balance = xc_balance + v_amount
    WHERE id = v_recipient.id;

  RETURN jsonb_build_object(
    'ok', true,
    'transfer_id', v_transfer_id,
    'reference', v_ref,
    'amount', v_amount,
    'recipient_username', v_recipient.username,
    'sender_xc_balance', v_sender.xc_balance - v_amount,
    'recipient_xc_balance', v_recipient.xc_balance + v_amount
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION xc_transfer(text, numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION xc_transfer(text, numeric, text) TO authenticated;

-- =====================================================
-- 5. list_xc_transfers — user's own transfer history
-- =====================================================

CREATE OR REPLACE FUNCTION list_xc_transfers(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'reference', t.reference, 'amount', t.amount,
    'status', t.status, 'created_at', t.created_at, 'completed_at', t.completed_at,
    'direction', CASE WHEN t.sender_id = auth.uid() THEN 'sent' ELSE 'received' END,
    'sender_username', ps.username,
    'recipient_username', pr.username
  ) ORDER BY t.created_at DESC), '[]'::jsonb)
  FROM xc_transfers t
  LEFT JOIN profiles ps ON ps.id = t.sender_id
  LEFT JOIN profiles pr ON pr.id = t.recipient_id
  WHERE (t.sender_id = auth.uid() OR t.recipient_id = auth.uid())
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION list_xc_transfers(integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION list_xc_transfers(integer, integer) TO authenticated;

-- =====================================================
-- 6. admin_list_xc_transfers — admin view of all transfers
-- =====================================================

CREATE OR REPLACE FUNCTION admin_list_xc_transfers(p_limit integer DEFAULT 200, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'reference', t.reference, 'amount', t.amount,
    'status', t.status, 'created_at', t.created_at, 'completed_at', t.completed_at,
    'sender_id', t.sender_id, 'sender_username', ps.username,
    'recipient_id', t.recipient_id, 'recipient_username', pr.username
  ) ORDER BY t.created_at DESC), '[]'::jsonb)
  FROM xc_transfers t
  LEFT JOIN profiles ps ON ps.id = t.sender_id
  LEFT JOIN profiles pr ON pr.id = t.recipient_id
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_xc_transfers(integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_xc_transfers(integer, integer) TO authenticated;

-- =====================================================
-- 7. Update admin_list_transactions to include transfer types in filter
-- =====================================================

CREATE OR REPLACE FUNCTION admin_list_transactions(
  p_limit integer DEFAULT 200, p_offset integer DEFAULT 0,
  p_type text DEFAULT NULL, p_user_id uuid DEFAULT NULL,
  p_currency text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'user_id', t.user_id, 'username', p.username,
    'type', t.type, 'amount', t.amount, 'currency', t.currency,
    'usd_equivalent', t.usd_equivalent,
    'base_usd_amount', t.base_usd_amount,
    'reward_multiplier', t.reward_multiplier,
    'status', t.status, 'description', t.description,
    'reference', t.reference, 'created_at', t.created_at
  ) ORDER BY t.created_at DESC), '[]'::jsonb)
  FROM transactions t
  LEFT JOIN profiles p ON p.id = t.user_id
  WHERE (p_type IS NULL OR t.type = p_type)
  AND (p_user_id IS NULL OR t.user_id = p_user_id)
  AND (p_currency IS NULL OR t.currency = p_currency);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_transactions(integer, integer, text, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_transactions(integer, integer, text, uuid, text) TO authenticated;
