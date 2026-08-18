/*
 * XC Token System — dual-currency (USD + XC) extension.
 *
 * Architecture:
 * - profiles gains `xc_balance` (numeric, default 0) for XC token holdings.
 * - transactions gains `currency` column ('USD' default, 'XC' for earning rewards)
 *   and `usd_equivalent` for audit/reference (the original USD value of an XC reward).
 * - app_settings gains XC config columns: xc_token_name, xc_token_symbol,
 *   xc_per_usd, xc_conversion_enabled, xc_min_conversion, xc_max_conversion.
 * - usd_to_xc(p_amount_usd) — pure function, reads rate from app_settings.
 * - convert_usd_to_xc(p_amount_usd) — user-facing atomic USD→XC conversion RPC
 *   with row locking, idempotency, overdraft protection.
 * - Earning functions (ptc_claim, task_submit, admin_review_task,
 *   offer_process_conversion) modified to credit XC instead of USD.
 * - USD functions (deposits, withdrawals, advertiser, referral commissions)
 *   remain unchanged — all use currency='USD' (the column default).
 * - Existing transactions backfilled to currency='USD'.
 */

-- =====================================================
-- 1. Schema changes
-- =====================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS xc_balance numeric(18,8) NOT NULL DEFAULT 0;

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'USD'
    CHECK (currency IN ('USD','XC'));

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS usd_equivalent numeric(18,8) DEFAULT NULL;

-- Backfill existing rows as USD
UPDATE transactions SET currency = 'USD' WHERE currency IS NULL OR currency = '';

-- App settings for XC
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_token_name text NOT NULL DEFAULT 'XC';
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_token_symbol text NOT NULL DEFAULT 'XC';
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_per_usd numeric(18,8) NOT NULL DEFAULT 5000;
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_conversion_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_min_conversion numeric(18,8) NOT NULL DEFAULT 1;
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS xc_max_conversion numeric(18,8) NOT NULL DEFAULT 1000;

-- =====================================================
-- 2. Helper: usd_to_xc
-- =====================================================

CREATE OR REPLACE FUNCTION usd_to_xc(p_amount_usd numeric)
RETURNS numeric(18,8)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT round(p_amount_usd * (SELECT xc_per_usd FROM app_settings WHERE id = 1), 8);
$$;

REVOKE EXECUTE ON FUNCTION usd_to_xc(numeric) FROM anon;
GRANT EXECUTE ON FUNCTION usd_to_xc(numeric) TO authenticated;

-- =====================================================
-- 3. convert_usd_to_xc — user-facing atomic conversion
-- =====================================================

CREATE OR REPLACE FUNCTION convert_usd_to_xc(p_amount_usd numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_settings app_settings%ROWTYPE;
  v_xc_amount numeric(18,8);
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_settings FROM app_settings WHERE id = 1;
  IF NOT v_settings.xc_conversion_enabled THEN
    RAISE EXCEPTION 'USD to XC conversion is currently disabled';
  END IF;

  IF p_amount_usd IS NULL OR p_amount_usd <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;
  IF p_amount_usd < v_settings.xc_min_conversion THEN
    RAISE EXCEPTION 'Minimum conversion is %', v_settings.xc_min_conversion;
  END IF;
  IF p_amount_usd > v_settings.xc_max_conversion THEN
    RAISE EXCEPTION 'Maximum conversion is %', v_settings.xc_max_conversion;
  END IF;
  IF p_amount_usd > v_profile.available_balance THEN
    RAISE EXCEPTION 'Insufficient available balance';
  END IF;

  v_xc_amount := usd_to_xc(p_amount_usd);
  IF v_xc_amount <= 0 THEN RAISE EXCEPTION 'Conversion produced zero XC'; END IF;

  -- Deduct USD from available_balance
  UPDATE profiles
    SET available_balance = available_balance - p_amount_usd,
        xc_balance = xc_balance + v_xc_amount
    WHERE id = auth.uid();

  -- Record USD deduction
  v_ref := 'xc_conv_usd:' || auth.uid()::text || ':' || extract(epoch from now())::bigint::text;
  INSERT INTO transactions (user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'xc_conversion', -p_amount_usd, 'USD', p_amount_usd,
      'xc_conversion', auth.uid(), v_ref,
      'USD to XC conversion (debit)', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  -- Record XC credit
  v_ref := 'xc_conv_xc:' || auth.uid()::text || ':' || extract(epoch from now())::bigint::text;
  INSERT INTO transactions (user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'xc_conversion', v_xc_amount, 'XC', p_amount_usd,
      'xc_conversion', auth.uid(), v_ref,
      'USD to XC conversion (credit)', 'completed')
    ON CONFLICT (reference) DO NOTHING;

  RETURN jsonb_build_object(
    'ok', true,
    'usd_amount', p_amount_usd,
    'xc_amount', v_xc_amount,
    'xc_balance', v_profile.xc_balance + v_xc_amount,
    'available_balance', v_profile.available_balance - p_amount_usd
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION convert_usd_to_xc(numeric) FROM anon;
GRANT EXECUTE ON FUNCTION convert_usd_to_xc(numeric) TO authenticated;

-- =====================================================
-- 4. Modify ptc_claim — credit XC instead of USD
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

  UPDATE ptc_ad_views SET status = 'completed', completed_at = now() WHERE id = p_view_id;

  v_xc_reward := usd_to_xc(v_view.reward);

  INSERT INTO transactions (user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ptc_reward', v_xc_reward, 'XC', v_view.reward,
      'ptc_ad_view', v_view.id, v_ref, 'PTC advertisement reward', 'completed')
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
    'transaction_id', v_tx_id,
    'completed_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_claim(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_claim(uuid) TO authenticated;

-- =====================================================
-- 5. Modify task_submit — credit XC for auto-approved tasks
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
    v_xc_reward := usd_to_xc(v_task.reward);
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status)
      VALUES (auth.uid(), 'task_reward', v_xc_reward, 'XC', v_task.reward,
        'task_completion', v_completion.id, v_ref, 'Task reward', 'completed')
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
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'reward', v_xc_reward, 'usd_equivalent', v_task.reward, 'completion_id', v_completion.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'pending', 'completion_id', v_completion.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

-- =====================================================
-- 6. Modify admin_review_task — credit XC on approval
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
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_completion FROM task_completions WHERE id = p_completion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task completion not found'; END IF;
  IF v_completion.status != 'pending' THEN RAISE EXCEPTION 'Task already reviewed'; END IF;

  IF p_approve THEN
    v_xc_reward := usd_to_xc(v_completion.reward);
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status)
      VALUES (v_completion.user_id, 'task_reward', v_xc_reward, 'XC', v_completion.reward,
        'task_completion', v_completion.id, v_ref, 'Task reward (approved)', 'completed')
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
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'reward', v_xc_reward, 'usd_equivalent', v_completion.reward);
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
-- 7. Modify offer_process_conversion — credit XC
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

    v_xc_reward := usd_to_xc(v_final_reward);

    v_ref := 'offer:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reward', v_xc_reward, 'XC', v_final_reward,
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

    v_xc_reward := usd_to_xc(v_final_reward);

    v_ref := 'offer_reversal:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, currency, usd_equivalent, reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reversal', -v_xc_reward, 'XC', v_final_reward,
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
-- 8. Update get_dashboard to include xc_balance
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
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'USD'
    AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_xc_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC'
    AND date_trunc('day', created_at) = current_date;

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
-- 9. Update admin_list_transactions to include currency + usd_equivalent
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
-- 10. Update admin_update_settings to accept XC params
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
  p_xc_max_conversion numeric DEFAULT NULL
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
    updated_at = now()
  WHERE id = 1;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text, text, text, numeric, boolean, numeric, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text, text, text, numeric, boolean, numeric, numeric) TO authenticated;

-- =====================================================
-- 11. Update admin_list_users to include xc_balance
-- =====================================================

CREATE OR REPLACE FUNCTION admin_list_users(p_search text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id, 'username', p.username, 'email', p.email, 'full_name', p.full_name,
    'country', p.country, 'role', p.role, 'status', p.status,
    'available_balance', p.available_balance, 'advertising_balance', p.advertising_balance,
    'xc_balance', p.xc_balance,
    'total_earned', p.total_earned, 'total_withdrawn', p.total_withdrawn,
    'total_deposited', p.total_deposited, 'ptc_views', p.ptc_views,
    'tasks_completed', p.tasks_completed, 'created_at', p.created_at,
    'ban_reason', p.ban_reason, 'banned_at', p.banned_at, 'banned_by', p.banned_by,
    'referrer_username', COALESCE((SELECT pr.username FROM profiles pr WHERE pr.id = p.referred_by), '')
  ) ORDER BY p.created_at DESC), '[]'::jsonb)
  FROM profiles p
  WHERE p_search IS NULL
    OR p.username ILIKE '%' || p_search || '%'
    OR p.email ILIKE '%' || p_search || '%'
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;
