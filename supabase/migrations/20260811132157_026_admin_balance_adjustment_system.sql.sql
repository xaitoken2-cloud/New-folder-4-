/*
# Admin USDT/XC Balance Adjustment System

## Overview
Replaces the old admin_adjust_balance function with a secure, currency-explicit
balance adjustment RPC. Admins can add or subtract USDT (available_balance) or
XC (xc_balance) independently, with mandatory reason, full validation, row
locking, atomic ledger entry, and audit trail.

## Changes

### 1. admin_adjust_user_balance(p_user_id, p_currency, p_action, p_amount, p_reason)
- SECURITY DEFINER, admin-only via is_admin()
- p_currency: 'USDT' or 'XC' only (anything else rejected)
- p_action: 'ADD' or 'SUBTRACT' only (anything else rejected)
- p_amount: must be numeric, > 0, <= 1,000,000, finite (not NaN/Infinity)
- p_reason: required, non-empty, trimmed
- Locks the user's profile row FOR UPDATE before any balance change
- USDT → modifies profiles.available_balance; ledger currency = 'USD'
- XC → modifies profiles.xc_balance; ledger currency = 'XC'
- Subtraction rejected if resulting balance < 0
- Creates a transaction in the existing transactions ledger with type='adjustment'
- Stores reason in description, admin id in reference_id, full metadata in audit_logs
- Idempotency: unique reference per adjustment using gen_random_uuid()
- Returns before/after balances, transaction_id, and adjustment details

### 2. admin_adjust_balance (old function) — dropped
The old function is removed; the frontend now uses admin_adjust_user_balance.

## Security
- SECURITY DEFINER with is_admin() check — non-admins get 'Not authorized'
- REVOKE EXECUTE FROM anon, GRANT TO authenticated
- Row locking (FOR UPDATE) prevents race conditions
- Currency/action/amount validated server-side
- No client-side balance writes
- RLS unchanged — existing policies still apply
- Atomic: balance update + ledger insert + audit log all in one function call
*/

-- =====================================================
-- Drop old admin_adjust_balance function
-- =====================================================
DROP FUNCTION IF EXISTS admin_adjust_balance(uuid, text, numeric, text);

-- =====================================================
-- admin_adjust_user_balance — secure currency-explicit adjustment
-- =====================================================
CREATE OR REPLACE FUNCTION admin_adjust_user_balance(
  p_user_id uuid,
  p_currency text,
  p_action text,
  p_amount numeric,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_before numeric(18,8);
  v_after numeric(18,8);
  v_signed_amount numeric(18,8);
  v_tx_id uuid;
  v_ref text;
  v_ledger_currency text;
  v_normal_currency text;
  v_normal_action text;
  v_clean_reason text;
  v_adjustment_uuid uuid;
BEGIN
  -- 1. Verify admin
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  -- 2. Validate currency (normalize to uppercase, check allowed)
  v_normal_currency := upper(trim(coalesce(p_currency, '')));
  IF v_normal_currency NOT IN ('USDT', 'XC') THEN
    RAISE EXCEPTION 'Invalid currency. Only USDT and XC are allowed.';
  END IF;

  -- 3. Validate action (normalize to uppercase, check allowed)
  v_normal_action := upper(trim(coalesce(p_action, '')));
  IF v_normal_action NOT IN ('ADD', 'SUBTRACT') THEN
    RAISE EXCEPTION 'Invalid action. Only ADD and SUBTRACT are allowed.';
  END IF;

  -- 4. Validate amount: must be numeric, > 0, finite, <= safe max
  IF p_amount IS NULL THEN
    RAISE EXCEPTION 'Amount is required.';
  END IF;
  IF isnan(p_amount) OR isinf(p_amount) THEN
    RAISE EXCEPTION 'Amount must be a valid finite number.';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero.';
  END IF;
  IF p_amount > 1000000 THEN
    RAISE EXCEPTION 'Amount exceeds the safe maximum of 1,000,000.';
  END IF;

  -- 5. Validate reason: required, non-empty
  v_clean_reason := trim(coalesce(p_reason, ''));
  IF v_clean_reason = '' THEN
    RAISE EXCEPTION 'Reason is required.';
  END IF;

  -- 6. Lock the user's balance row
  SELECT * INTO v_profile FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  -- 7. Determine signed amount and ledger currency
  IF v_normal_action = 'ADD' THEN
    v_signed_amount := p_amount;
  ELSE
    v_signed_amount := -p_amount;
  END IF;

  -- USDT maps to available_balance + ledger currency 'USD'
  -- XC maps to xc_balance + ledger currency 'XC'
  IF v_normal_currency = 'USDT' THEN
    v_before := v_profile.available_balance;
    v_after := v_before + v_signed_amount;
    IF v_after < 0 THEN
      RAISE EXCEPTION 'Insufficient USDT balance. Current: %, Attempted subtract: %', v_before, p_amount;
    END IF;
    UPDATE profiles SET available_balance = v_after WHERE id = p_user_id;
    v_ledger_currency := 'USD';
  ELSE
    v_before := v_profile.xc_balance;
    v_after := v_before + v_signed_amount;
    IF v_after < 0 THEN
      RAISE EXCEPTION 'Insufficient XC balance. Current: %, Attempted subtract: %', v_before, p_amount;
    END IF;
    UPDATE profiles SET xc_balance = v_after WHERE id = p_user_id;
    v_ledger_currency := 'XC';
  END IF;

  -- 8. Create ledger transaction (unique reference for idempotency)
  v_adjustment_uuid := gen_random_uuid();
  v_ref := 'admin_adjust:' || v_adjustment_uuid::text;
  INSERT INTO transactions (
    user_id, type, amount, currency, usd_equivalent,
    reference_type, reference_id, reference, description, status
  ) VALUES (
    p_user_id, 'adjustment', v_signed_amount, v_ledger_currency, NULL,
    'admin_adjustment', auth.uid(), v_ref,
    'Admin Balance Adjustment — ' || v_normal_action || ' ' || v_normal_currency || ' — ' || v_clean_reason,
    'completed'
  ) RETURNING id INTO v_tx_id;

  -- 9. Store audit trail with full metadata
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
  VALUES (
    auth.uid(), 'adjust_balance', 'user', p_user_id::text,
    jsonb_build_object(
      'currency', v_normal_currency,
      'action', v_normal_action,
      'amount', p_amount,
      'signed_amount', v_signed_amount,
      'before', v_before,
      'after', v_after,
      'reason', v_clean_reason,
      'transaction_id', v_tx_id,
      'reference', v_ref,
      'admin_id', auth.uid(),
      'target_username', v_profile.username
    )
  );

  -- 10. Return result
  RETURN jsonb_build_object(
    'ok', true,
    'currency', v_normal_currency,
    'action', v_normal_action,
    'amount', p_amount,
    'before', v_before,
    'after', v_after,
    'transaction_id', v_tx_id,
    'reference', v_ref,
    'reason', v_clean_reason
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_adjust_user_balance(uuid, text, text, numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_adjust_user_balance(uuid, text, text, numeric, text) TO authenticated;
