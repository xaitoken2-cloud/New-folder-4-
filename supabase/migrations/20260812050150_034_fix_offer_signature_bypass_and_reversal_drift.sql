-- =====================================================
-- 034: Fix offer signature bypass and reversal drift
--
-- BUG 1: offer_process_conversion was granted TO authenticated
--   (migrations 022 & 024), allowing any logged-in user to call it
--   directly via supabase.rpc() and credit their own XC balance,
--   bypassing webhook signature verification.
--
-- BUG 2: The webhook called offer_process_conversion on rejected
--   signatures "to log the attempt," but that function credits
--   rewards regardless of signature validity.
--
-- BUG 3: The reversal branch recomputed the XC debit via
--   compute_xc_reward(), which reads the CURRENT reward_multiplier.
--   If the multiplier changed between conversion and reversal,
--   the debited amount drifted from the credited amount.
--
-- Fixes:
--   - Add offer_log_rejected_postback(): audit-only, inserts a
--     'rejected' row into offer_conversions, never touches
--     profiles or transactions.
--   - Re-create offer_process_conversion identical to its current
--     logic, except the reversal branch reads the XC amount from
--     the original 'offer_reward' transaction row instead of
--     recomputing it.
--   - Lock grants: REVOKE FROM PUBLIC, anon, authenticated
--     (service-role only, matching original intent of 020/021).
-- =====================================================

-- =====================================================
-- 1. offer_log_rejected_postback — audit-only rejected postback log
-- =====================================================

CREATE OR REPLACE FUNCTION offer_log_rejected_postback(
  p_provider_slug text,
  p_tracking_id text,
  p_conversion_id text,
  p_reward numeric,
  p_revenue numeric DEFAULT 0,
  p_event_type text DEFAULT 'conversion',
  p_raw jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider offer_providers%ROWTYPE;
  v_session offer_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_provider FROM offer_providers WHERE slug = p_provider_slug;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Provider not found');
  END IF;

  SELECT * INTO v_session FROM offer_sessions WHERE tracking_id = p_tracking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Session not found for tracking_id');
  END IF;

  INSERT INTO offer_conversions (
    session_id, user_id, provider_id, provider_conversion_id,
    event_type, reward, revenue, status, raw_payload
  ) VALUES (
    v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
    p_event_type, p_reward, p_revenue, 'rejected', p_raw
  ) ON CONFLICT (provider_id, provider_conversion_id, event_type) DO NOTHING;

  RETURN jsonb_build_object('status', 'rejected', 'reason', 'Signature verification failed');
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_log_rejected_postback(text, text, text, numeric, numeric, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_log_rejected_postback(text, text, text, numeric, numeric, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_log_rejected_postback(text, text, text, numeric, numeric, text, jsonb) FROM authenticated;

-- =====================================================
-- 2. Re-create offer_process_conversion
--    Identical to current logic (migration 024) except:
--    a) Reversal branch reads XC amount from the original
--       'offer_reward' transaction row instead of recomputing
--       via compute_xc_reward().
--    b) Grants locked to service-role only.
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

    -- Read the XC amount from the original 'offer_reward' transaction
    -- instead of recomputing via compute_xc_reward(), so a multiplier
    -- change between conversion and reversal does not cause drift.
    SELECT amount INTO v_xc_reward FROM transactions
    WHERE user_id = v_session.user_id
      AND type = 'offer_reward'
      AND reference = 'offer:' || v_session.id::text
    LIMIT 1;

    IF v_xc_reward IS NULL THEN
      INSERT INTO offer_conversions (
        session_id, user_id, provider_id, provider_conversion_id,
        event_type, reward, revenue, status, raw_payload
      ) VALUES (
        v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
        'reversal', v_final_reward, p_revenue, 'rejected', p_raw
      ) ON CONFLICT DO NOTHING;
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'Original reward transaction not found');
    END IF;

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

-- Lock to service-role only — no anon or authenticated access
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM authenticated;
