/*
# XC Reward Multiplier Economy

## Overview
Implements the centralized 10x reward multiplier system for all earner rewards.
1 XC = $1 USD. Eligible earning rewards receive base_usd_reward × reward_multiplier (default 10).

## Changes

### 1. app_settings — new columns
- `reward_multiplier` numeric(18,8) DEFAULT 10 — the multiplier applied to base USD rewards
- `xc_value_usd` numeric(18,8) DEFAULT 1.00 — the USD value of 1 XC token

### 2. transactions — new columns
- `base_usd_amount` numeric(18,8) DEFAULT NULL — the original base USD reward before multiplier
- `reward_multiplier` numeric(18,8) DEFAULT NULL — the multiplier applied at time of transaction

### 3. compute_xc_reward(p_base_usd) — centralized server-side reward calculation
- Reads reward_multiplier from app_settings
- Returns base_usd × reward_multiplier
- This is the SINGLE source of truth for all earning reward calculations
- Historical transactions retain their original base_usd_amount and reward_multiplier values

### 4. Updated earning functions to use compute_xc_reward():
- ptc_claim: credits base × multiplier as XC, records base_usd_amount + reward_multiplier
- task_submit: same for auto-approved tasks
- admin_review_task: same for admin-approved tasks
- offer_process_conversion: applies provider margin FIRST, then multiplier

### 5. usd_to_xc() — kept for the USD→XC conversion feature only
- Now uses xc_value_usd (1 XC = $1) instead of xc_per_usd
- This is NOT used for earning rewards — those use compute_xc_reward()

### 6. admin_update_settings — accepts reward_multiplier + xc_value_usd params

### 7. get_dashboard — includes xc_total_earned

## Security
- All functions remain SECURITY DEFINER with auth.uid() checks
- No client-side reward calculation
- Row locking preserved (FOR UPDATE)
- Idempotency preserved (ON CONFLICT reference DO NOTHING)
- RLS unchanged — existing policies still apply
- No new tables — only additive column changes

## Important Notes
- Historical transactions are NOT modified — they retain NULL base_usd_amount/reward_multiplier
- Changing the multiplier does NOT alter historical transactions
- Advertiser economics remain USD — no changes to campaign spending
- Referral/deposit commissions remain USD — no multiplier applied
- Deposits and withdrawals remain USD
*/

-- =====================================================
-- 1. app_settings — add reward_multiplier and xc_value_usd
-- =====================================================

ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS reward_multiplier numeric(18,8) NOT NULL DEFAULT 10;

ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_value_usd numeric(18,8) NOT NULL DEFAULT 1.00;

-- Fix xc_per_usd default: 1 XC = $1, so xc_per_usd should be 1 (not 5000)
-- This only affects the optional USD→XC conversion feature, NOT earning rewards
UPDATE app_settings SET xc_per_usd = 1 WHERE xc_per_usd = 5000;

-- =====================================================
-- 2. transactions — add base_usd_amount and reward_multiplier
-- =====================================================

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS base_usd_amount numeric(18,8) DEFAULT NULL;

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS reward_multiplier numeric(18,8) DEFAULT NULL;

-- =====================================================
-- 3. compute_xc_reward — centralized server-side reward calculation
-- =====================================================

CREATE OR REPLACE FUNCTION compute_xc_reward(p_base_usd numeric)
RETURNS numeric(18,8)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT round(
    p_base_usd * (SELECT reward_multiplier FROM app_settings WHERE id = 1),
    8
  );
$$;

REVOKE EXECUTE ON FUNCTION compute_xc_reward(numeric) FROM anon;
GRANT EXECUTE ON FUNCTION compute_xc_reward(numeric) TO authenticated;

-- =====================================================
-- 4. usd_to_xc — use xc_value_usd (for conversion feature only)
-- =====================================================

CREATE OR REPLACE FUNCTION usd_to_xc(p_amount_usd numeric)
RETURNS numeric(18,8)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT round(
    p_amount_usd / (SELECT xc_value_usd FROM app_settings WHERE id = 1),
    8
  );
$$;

REVOKE EXECUTE ON FUNCTION usd_to_xc(numeric) FROM anon;
GRANT EXECUTE ON FUNCTION usd_to_xc(numeric) TO authenticated;

-- =====================================================
-- 5. ptc_claim — use compute_xc_reward, record base_usd + multiplier
-- =====================================================

CREATE OR REPLACE FUNCTION ptc_claim(p_view_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_view ptc_ad_views%ROWTYPE;
  v_ad ptc_ads%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_elapsed numeric;
  v_xc_reward numeric(18,8);
  v_multiplier numeric(18,8);
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_view FROM ptc_ad_views WHERE id = p_view_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'View session not found'; END IF;
  IF v_view.user_id != auth.uid() THEN RAISE EXCEPTION 'View does not belong to you'; END IF;
  IF v_view.status = 'completed' THEN RAISE EXCEPTION 'Reward already claimed'; END IF;
  IF v_view.status = 'expired' OR v_view.status = 'cancelled' THEN RAISE EXCEPTION 'View session is no longer valid'; END IF;

  v_elapsed := extract(epoch from (now() - v_view.started_at));
  IF v_elapsed < v_view.required_duration THEN
    RAISE EXCEPTION 'View duration not yet satisfied (elapsed %, required %)', v_elapsed, v_view.required_duration;
  END IF;

  SELECT * INTO v_ad FROM ptc_ads WHERE id = v_view.ptc_ad_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;
  IF NOT v_ad.active THEN RAISE EXCEPTION 'Advertisement is no longer active'; END IF;
  IF v_ad.end_date IS NOT NULL AND now() > v_ad.end_date THEN RAISE EXCEPTION 'Advertisement has expired'; END IF;
  IF v_ad.total_view_limit > 0 AND v_ad.total_views >= v_ad.total_view_limit THEN
    RAISE EXCEPTION 'Total view limit reached for this advertisement';
  END IF;

  v_ref := 'ptc:' || v_view.id::text;
  v_multiplier := (SELECT reward_multiplier FROM app_settings WHERE id = 1);
  v_xc_reward := compute_xc_reward(v_view.reward);

  UPDATE ptc_ad_views SET status = 'completed', completed_at = now() WHERE id = p_view_id;

  INSERT INTO transactions (
    user_id, type, amount, currency, usd_equivalent,
    base_usd_amount, reward_multiplier,
    reference_type, reference_id, reference, description, status
  ) VALUES (
    auth.uid(), 'ptc_reward', v_xc_reward, 'XC', v_view.reward,
    v_view.reward, v_multiplier,
    'ptc_ad_view', v_view.id, v_ref, 'PTC advertisement reward', 'completed'
  )
  ON CONFLICT (reference) DO NOTHING
  RETURNING id INTO v_tx_id;

  IF v_tx_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_claimed', true, 'reward', v_xc_reward, 'usd_equivalent', v_view.reward);
  END IF;

  UPDATE profiles
    SET xc_balance = xc_balance + v_xc_reward,
        total_earned = total_earned + v_view.reward,
        ptc_views = ptc_views + 1
    WHERE id = auth.uid();

  UPDATE ptc_ads SET total_views = total_views + 1 WHERE id = v_ad.id;

  PERFORM credit_referral_commission(auth.uid(), v_view.reward, 'ptc_reward', v_ref);

  RETURN jsonb_build_object(
    'ok', true,
    'reward', v_xc_reward,
    'usd_equivalent', v_view.reward,
    'base_usd_amount', v_view.reward,
    'reward_multiplier', v_multiplier,
    'transaction_id', v_tx_id,
    'completed_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_claim(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_claim(uuid) TO authenticated;

-- =====================================================
-- 6. task_submit — use compute_xc_reward, record base_usd + multiplier
-- =====================================================

CREATE OR REPLACE FUNCTION task_submit(p_task_id uuid, p_proof_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_today_count integer;
  v_xc_reward numeric(18,8);
  v_multiplier numeric(18,8);
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_task FROM tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
  IF NOT v_task.active THEN RAISE EXCEPTION 'Task is not active'; END IF;
  IF v_task.start_date IS NOT NULL AND now() < v_task.start_date THEN RAISE EXCEPTION 'Task not yet available'; END IF;
  IF v_task.end_date IS NOT NULL AND now() > v_task.end_date THEN RAISE EXCEPTION 'Task has expired'; END IF;
  IF v_task.total_limit > 0 AND v_task.total_completions >= v_task.total_limit THEN
    RAISE EXCEPTION 'Task completion limit reached';
  END IF;

  IF v_task.daily_limit > 0 THEN
    SELECT count(*) INTO v_today_count FROM task_completions
      WHERE user_id = auth.uid() AND task_id = p_task_id
        AND date_trunc('day', created_at) = current_date;
    IF v_today_count >= v_task.daily_limit THEN RAISE EXCEPTION 'Daily limit reached for this task'; END IF;
  END IF;

  INSERT INTO task_completions (user_id, task_id, proof_text, reward, status)
    VALUES (auth.uid(), p_task_id, COALESCE(p_proof_text, ''), v_task.reward,
      CASE WHEN v_task.proof_required THEN 'pending' ELSE 'approved' END)
    ON CONFLICT (user_id, task_id) DO NOTHING
    RETURNING * INTO v_completion;

  IF v_completion IS NULL THEN
    RAISE EXCEPTION 'You have already submitted this task';
  END IF;

  UPDATE tasks SET total_completions = total_completions + 1 WHERE id = p_task_id;

  IF NOT v_task.proof_required THEN
    v_multiplier := (SELECT reward_multiplier FROM app_settings WHERE id = 1);
    v_xc_reward := compute_xc_reward(v_task.reward);
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent,
      base_usd_amount, reward_multiplier,
      reference_type, reference_id, reference, description, status
    ) VALUES (
      auth.uid(), 'task_reward', v_xc_reward, 'XC', v_task.reward,
      v_task.reward, v_multiplier,
      'task_completion', v_completion.id, v_ref, 'Task reward', 'completed'
    )
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET xc_balance = xc_balance + v_xc_reward,
            total_earned = total_earned + v_task.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = auth.uid();
      PERFORM credit_referral_commission(auth.uid(), v_task.reward, 'task_reward', v_ref);
    END IF;
    RETURN jsonb_build_object(
      'ok', true, 'status', 'approved', 'reward', v_xc_reward,
      'usd_equivalent', v_task.reward, 'base_usd_amount', v_task.reward,
      'reward_multiplier', v_multiplier, 'completion_id', v_completion.id
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'pending', 'completion_id', v_completion.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

-- =====================================================
-- 7. admin_review_task — use compute_xc_reward, record base_usd + multiplier
-- =====================================================

CREATE OR REPLACE FUNCTION admin_review_task(p_completion_id uuid, p_approve boolean, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_xc_reward numeric(18,8);
  v_multiplier numeric(18,8);
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_completion FROM task_completions WHERE id = p_completion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task completion not found'; END IF;
  IF v_completion.status != 'pending' THEN RAISE EXCEPTION 'Task already reviewed'; END IF;

  IF p_approve THEN
    v_multiplier := (SELECT reward_multiplier FROM app_settings WHERE id = 1);
    v_xc_reward := compute_xc_reward(v_completion.reward);
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent,
      base_usd_amount, reward_multiplier,
      reference_type, reference_id, reference, description, status
    ) VALUES (
      v_completion.user_id, 'task_reward', v_xc_reward, 'XC', v_completion.reward,
      v_completion.reward, v_multiplier,
      'task_completion', v_completion.id, v_ref, 'Task reward (approved)', 'completed'
    )
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET xc_balance = xc_balance + v_xc_reward,
            total_earned = total_earned + v_completion.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = v_completion.user_id;
      PERFORM credit_referral_commission(v_completion.user_id, v_completion.reward, 'task_reward', v_ref);
    END IF;

    UPDATE task_completions SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'approve_task', 'task_completion', p_completion_id::text, jsonb_build_object('reward', v_completion.reward));
    RETURN jsonb_build_object(
      'ok', true, 'status', 'approved', 'reward', v_xc_reward,
      'usd_equivalent', v_completion.reward, 'base_usd_amount', v_completion.reward,
      'reward_multiplier', v_multiplier
    );
  ELSE
    UPDATE task_completions SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'reject_task', 'task_completion', p_completion_id::text, jsonb_build_object('note', p_note));
    RETURN jsonb_build_object('ok', true, 'status', 'rejected');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) TO authenticated;

-- =====================================================
-- 8. offer_process_conversion — apply provider margin THEN multiplier
-- =====================================================

CREATE OR REPLACE FUNCTION offer_process_conversion(
  p_provider_slug text, p_tracking_id text, p_conversion_id text,
  p_reward numeric, p_revenue numeric DEFAULT 0,
  p_event_type text DEFAULT 'conversion', p_raw jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider offer_providers%ROWTYPE;
  v_session offer_sessions%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_tx_id uuid;
  v_final_reward numeric;
  v_xc_reward numeric(18,8);
  v_conversion_exists boolean;
  v_ref text;
  v_payload_currency text;
  v_max_reward_mult numeric := 5.0;
  v_multiplier numeric(18,8);
BEGIN
  SELECT * INTO v_provider FROM offer_providers WHERE slug = p_provider_slug AND enabled = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Provider not found or disabled');
  END IF;

  SELECT * INTO v_session FROM offer_sessions WHERE tracking_id = p_tracking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Session not found for tracking_id');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM offer_conversions
    WHERE provider_id = v_provider.id
    AND provider_conversion_id = p_conversion_id
    AND event_type = p_event_type
  ) INTO v_conversion_exists;

  IF v_conversion_exists THEN
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, p_reward, p_revenue, 'duplicate', p_raw
    ) ON CONFLICT (provider_id, provider_conversion_id, event_type) DO NOTHING;
    RETURN jsonb_build_object('status', 'duplicate', 'reason', 'Conversion already processed');
  END IF;

  -- Apply provider margin FIRST (before XC multiplier)
  v_final_reward := p_reward * (v_provider.reward_margin_percent / 100.0);

  IF v_final_reward <= 0 THEN
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, v_final_reward, p_revenue, 'rejected', p_raw
    ) ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Reward must be greater than zero');
  END IF;

  IF v_provider.reward_margin_percent < 0 OR v_provider.reward_margin_percent > 200 THEN
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, v_final_reward, p_revenue, 'rejected', p_raw
    ) ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Provider margin out of bounds');
  END IF;

  IF v_session.reward > 0 AND v_final_reward > (v_session.reward * v_max_reward_mult) THEN
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, v_final_reward, p_revenue, 'rejected', p_raw
    ) ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Reward exceeds sanity bound (5x session reward)');
  END IF;

  v_payload_currency := COALESCE(p_raw->>'currency', p_raw->>'currency_code', '');
  IF v_payload_currency != '' AND upper(v_payload_currency) != upper(v_session.currency_code) THEN
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, v_final_reward, p_revenue, 'rejected', p_raw
    ) ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Currency mismatch');
  END IF;

  v_multiplier := (SELECT reward_multiplier FROM app_settings WHERE id = 1);

  IF p_event_type = 'conversion' THEN
    IF v_session.status IN ('completed', 'reversed') THEN
      INSERT INTO offer_conversions (
        session_id, user_id, provider_id, provider_conversion_id,
        event_type, reward, revenue, status, raw_payload
      ) VALUES (
        v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
        p_event_type, v_final_reward, p_revenue, 'rejected', p_raw
      ) ON CONFLICT DO NOTHING;
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'Session already ' || v_session.status);
    END IF;

    SELECT * INTO v_profile FROM profiles WHERE id = v_session.user_id FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'User profile not found');
    END IF;

    -- Apply XC multiplier AFTER provider margin
    v_xc_reward := compute_xc_reward(v_final_reward);

    v_ref := 'offer:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent,
      base_usd_amount, reward_multiplier,
      reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reward', v_xc_reward, 'XC', v_final_reward,
      v_final_reward, v_multiplier,
      'offer_session', v_session.id::text, v_ref,
      'Offer Reward — ' || v_session.provider_slug, 'completed'
    ) ON CONFLICT (reference) DO NOTHING RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET xc_balance = xc_balance + v_xc_reward,
            total_earned = total_earned + v_final_reward
        WHERE id = v_session.user_id;
    END IF;

    UPDATE offer_sessions
      SET status = 'completed',
          completed_at = now(),
          provider_conversion_id = p_conversion_id,
          revenue = p_revenue
      WHERE id = v_session.id;

    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      'conversion', v_final_reward, p_revenue, 'processed', p_raw
    ) ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
      'status', 'processed',
      'session_id', v_session.id,
      'reward', v_xc_reward,
      'usd_equivalent', v_final_reward,
      'base_usd_amount', v_final_reward,
      'reward_multiplier', v_multiplier,
      'transaction_id', v_tx_id
    );

  ELSIF p_event_type = 'reversal' THEN
    IF v_session.status != 'completed' THEN
      INSERT INTO offer_conversions (
        session_id, user_id, provider_id, provider_conversion_id,
        event_type, reward, revenue, status, raw_payload
      ) VALUES (
        v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
        'reversal', v_final_reward, p_revenue, 'rejected', p_raw
      ) ON CONFLICT DO NOTHING;
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'Session not in completed state');
    END IF;

    SELECT * INTO v_profile FROM profiles WHERE id = v_session.user_id FOR UPDATE;

    v_xc_reward := compute_xc_reward(v_final_reward);

    v_ref := 'offer_reversal:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent,
      base_usd_amount, reward_multiplier,
      reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reversal', -v_xc_reward, 'XC', v_final_reward,
      v_final_reward, v_multiplier,
      'offer_session', v_session.id::text, v_ref,
      'Offer Reversal — ' || v_session.provider_slug, 'reversed'
    ) ON CONFLICT (reference) DO NOTHING RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET xc_balance = xc_balance - v_xc_reward,
            total_earned = total_earned - v_final_reward
        WHERE id = v_session.user_id;
    END IF;

    UPDATE offer_sessions
      SET status = 'reversed',
          reversed_at = now()
      WHERE id = v_session.id;

    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      'reversal', v_final_reward, p_revenue, 'processed', p_raw
    ) ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
      'status', 'processed',
      'session_id', v_session.id,
      'reversed_reward', v_xc_reward,
      'usd_equivalent', v_final_reward,
      'base_usd_amount', v_final_reward,
      'reward_multiplier', v_multiplier,
      'transaction_id', v_tx_id
    );

  ELSE
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Unknown event type');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) TO authenticated;

-- =====================================================
-- 9. get_dashboard — include xc_total_earned
-- =====================================================

CREATE OR REPLACE FUNCTION get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_today_earned numeric;
  v_referral_earned numeric;
  v_pending_count integer;
  v_series jsonb;
  v_xc_today_earned numeric;
  v_xc_total_earned numeric;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'USD'
    AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_xc_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC'
    AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_xc_total_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC';

  SELECT COALESCE(sum(amount), 0) INTO v_referral_earned FROM transactions
  WHERE user_id = auth.uid() AND type = 'referral_reward' AND status = 'completed';

  SELECT count(*) INTO v_pending_count FROM withdrawals WHERE user_id = auth.uid() AND status = 'pending';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d, 'amount', coalesce(amt, 0)) ORDER BY d), '[]'::jsonb) INTO v_series
  FROM (
    SELECT generate_series(current_date - interval '6 days', current_date, '1 day')::date AS d
  ) days
  LEFT JOIN LATERAL (
    SELECT sum(amount) AS amt FROM transactions
    WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC'
      AND date_trunc('day', created_at) = d::timestamptz
  ) s ON true;

  RETURN jsonb_build_object(
    'available_balance', v_profile.available_balance,
    'pending_balance', v_profile.pending_balance,
    'xc_balance', v_profile.xc_balance,
    'total_earned', v_profile.total_earned,
    'xc_total_earned', v_xc_total_earned,
    'total_withdrawn', v_profile.total_withdrawn,
    'total_deposited', v_profile.total_deposited,
    'today_earned', v_today_earned,
    'xc_today_earned', v_xc_today_earned,
    'referral_earned', v_referral_earned,
    'ptc_views', v_profile.ptc_views,
    'tasks_completed', v_profile.tasks_completed,
    'pending_withdrawals', v_pending_count,
    'role', v_profile.role,
    'status', v_profile.status,
    'earnings_series', v_series
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_dashboard() FROM anon;
GRANT EXECUTE ON FUNCTION get_dashboard() TO authenticated;

-- =====================================================
-- 10. admin_list_transactions — include base_usd_amount + reward_multiplier
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

-- =====================================================
-- 11. admin_update_settings — accept reward_multiplier + xc_value_usd
-- =====================================================

CREATE OR REPLACE FUNCTION admin_update_settings(
  p_referral_commission_percent numeric DEFAULT NULL,
  p_referral_deposit_commission_percent numeric DEFAULT NULL,
  p_min_withdrawal numeric DEFAULT NULL,
  p_max_withdrawal numeric DEFAULT NULL,
  p_withdrawal_cooldown_minutes integer DEFAULT NULL,
  p_ptc_daily_limit_per_ad integer DEFAULT NULL,
  p_task_daily_limit integer DEFAULT NULL,
  p_platform_name text DEFAULT NULL,
  p_xc_token_name text DEFAULT NULL,
  p_xc_token_symbol text DEFAULT NULL,
  p_xc_per_usd numeric DEFAULT NULL,
  p_xc_conversion_enabled boolean DEFAULT NULL,
  p_xc_min_conversion numeric DEFAULT NULL,
  p_xc_max_conversion numeric DEFAULT NULL,
  p_reward_multiplier numeric DEFAULT NULL,
  p_xc_value_usd numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE app_settings SET
    referral_commission_percent = COALESCE(p_referral_commission_percent, referral_commission_percent),
    referral_deposit_commission_percent = COALESCE(p_referral_deposit_commission_percent, referral_deposit_commission_percent),
    min_withdrawal = COALESCE(p_min_withdrawal, min_withdrawal),
    max_withdrawal = COALESCE(p_max_withdrawal, max_withdrawal),
    withdrawal_cooldown_minutes = COALESCE(p_withdrawal_cooldown_minutes, withdrawal_cooldown_minutes),
    ptc_daily_limit_per_ad = COALESCE(p_ptc_daily_limit_per_ad, ptc_daily_limit_per_ad),
    task_daily_limit = COALESCE(p_task_daily_limit, task_daily_limit),
    platform_name = COALESCE(p_platform_name, platform_name),
    xc_token_name = COALESCE(p_xc_token_name, xc_token_name),
    xc_token_symbol = COALESCE(p_xc_token_symbol, xc_token_symbol),
    xc_per_usd = COALESCE(p_xc_per_usd, xc_per_usd),
    xc_conversion_enabled = COALESCE(p_xc_conversion_enabled, xc_conversion_enabled),
    xc_min_conversion = COALESCE(p_xc_min_conversion, xc_min_conversion),
    xc_max_conversion = COALESCE(p_xc_max_conversion, xc_max_conversion),
    reward_multiplier = COALESCE(p_reward_multiplier, reward_multiplier),
    xc_value_usd = COALESCE(p_xc_value_usd, xc_value_usd),
    updated_at = now()
  WHERE id = 1;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text, text, text, numeric, boolean, numeric, numeric, numeric, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text, text, text, numeric, boolean, numeric, numeric, numeric, numeric) TO authenticated;
