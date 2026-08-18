/*
# Offer System Security & Sync Fixes

## Fix 2 — Remove hardcoded encryption key fallback
Replaces offer_admin_set_provider_secret and offer_get_postback_secret with
versions that raise an exception if app.secret_key is not configured, instead
of falling back to a hardcoded string.

## Fix 4 — Currency validation in offer_process_conversion
Adds a check: if the provider payload specifies a currency different from the
session's currency_code, the conversion is rejected with reason 'Currency mismatch'.

## Fix 5 — Reward/margin sanity bounds
Adds sanity checks before crediting:
- Reject if p_reward <= 0 for a conversion event
- Reject if v_final_reward exceeds 5x the session's original snapshot reward
- Reject if reward_margin_percent on the provider is outside 0–200
All rejections are recorded in offer_conversions with status='rejected'.

## Fix 3 (partial) — offer_admin_trigger_sync RPC
Adds an admin-only RPC to trigger the offer-sync edge function manually.
Also adds offer_get_api_key (service-role only) for the sync edge function.

## New column
- offer_providers.last_synced_at timestamptz — tracks last successful sync
*/

-- Add last_synced_at column to offer_providers
ALTER TABLE offer_providers ADD COLUMN IF NOT EXISTS last_synced_at timestamptz;

-- =============================================================
-- Fix 2: Replace offer_admin_set_provider_secret (no hardcoded key)
-- =============================================================
CREATE OR REPLACE FUNCTION offer_admin_set_provider_secret(
  p_provider_id uuid,
  p_secret_type text,
  p_secret_value text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_count int;
  v_encrypted text;
  v_key text;
BEGIN
  SELECT is_admin() INTO v_is_admin;
  IF NOT v_is_admin THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Require a real encryption key — no hardcoded fallback
  v_key := current_setting('app.secret_key', true);
  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'Encryption key not configured. Set app.secret_key via: ALTER DATABASE current_database() SET app.secret_key TO ''your-32-char-key'';';
  END IF;

  v_encrypted := pgp_sym_encrypt(p_secret_value, v_key);

  IF p_secret_type = 'api_key' THEN
    UPDATE offer_providers SET
      api_key_encrypted = v_encrypted,
      updated_at = now()
    WHERE id = p_provider_id
    RETURNING 1 INTO v_count;
  ELSIF p_secret_type = 'postback_secret' THEN
    UPDATE offer_providers SET
      postback_secret_encrypted = v_encrypted,
      updated_at = now()
    WHERE id = p_provider_id
    RETURNING 1 INTO v_count;
  ELSE
    RETURN jsonb_build_object('error', 'Unknown secret type');
  END IF;

  IF v_count IS NULL THEN
    RETURN jsonb_build_object('error', 'Provider not found');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_admin_set_provider_secret(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION offer_admin_set_provider_secret(uuid, text, text) TO authenticated;

-- =============================================================
-- Fix 2: Replace offer_get_postback_secret (no hardcoded key)
-- =============================================================
CREATE OR REPLACE FUNCTION offer_get_postback_secret(
  p_provider_slug text,
  p_secret_type text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_encrypted text;
  v_decrypted text;
  v_key text;
BEGIN
  IF p_secret_type = 'api_key' THEN
    SELECT api_key_encrypted INTO v_encrypted FROM offer_providers WHERE slug = p_provider_slug;
  ELSIF p_secret_type = 'postback_secret' THEN
    SELECT postback_secret_encrypted INTO v_encrypted FROM offer_providers WHERE slug = p_provider_slug;
  ELSE
    RETURN NULL;
  END IF;

  IF v_encrypted IS NULL THEN
    RETURN NULL;
  END IF;

  -- Require a real encryption key — no hardcoded fallback
  v_key := current_setting('app.secret_key', true);
  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'Encryption key not configured. Set app.secret_key via: ALTER DATABASE current_database() SET app.secret_key TO ''your-32-char-key'';';
  END IF;

  v_decrypted := pgp_sym_decrypt(v_encrypted::bytea, v_key);
  RETURN v_decrypted;
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM authenticated;

-- =============================================================
-- Fix 3: offer_get_api_key (service-role only, for offer-sync)
-- =============================================================
CREATE OR REPLACE FUNCTION offer_get_api_key(
  p_provider_slug text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_encrypted text;
  v_decrypted text;
  v_key text;
BEGIN
  SELECT api_key_encrypted INTO v_encrypted FROM offer_providers WHERE slug = p_provider_slug;

  IF v_encrypted IS NULL THEN
    RETURN NULL;
  END IF;

  v_key := current_setting('app.secret_key', true);
  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'Encryption key not configured.';
  END IF;

  v_decrypted := pgp_sym_decrypt(v_encrypted::bytea, v_key);
  RETURN v_decrypted;
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_get_api_key(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_get_api_key(text) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_get_api_key(text) FROM authenticated;

-- =============================================================
-- Fix 3: offer_admin_trigger_sync (admin-only)
-- Returns the URL of the offer-sync edge function for the admin UI to call
-- =============================================================
CREATE OR REPLACE FUNCTION offer_admin_trigger_sync(
  p_provider_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_provider_slug text;
  v_sync_url text;
BEGIN
  SELECT is_admin() INTO v_is_admin;
  IF NOT v_is_admin THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- If a specific provider is requested, get its slug
  IF p_provider_id IS NOT NULL THEN
    SELECT slug INTO v_provider_slug FROM offer_providers WHERE id = p_provider_id;
    IF v_provider_slug IS NULL THEN
      RETURN jsonb_build_object('error', 'Provider not found');
    END IF;
  END IF;

  -- Return the sync endpoint URL — the frontend will call it with the service role
  -- via an admin RPC that uses pg_net or the caller can invoke the edge function directly
  v_sync_url := current_setting('app.functions_url', true);
  IF v_sync_url IS NULL OR v_sync_url = '' THEN
    v_sync_url := '';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'sync_url', v_sync_url || '/functions/v1/offer-sync',
    'provider_slug', v_provider_slug
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_admin_trigger_sync(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION offer_admin_trigger_sync(uuid) TO authenticated;

-- =============================================================
-- Fix 3: offer_admin_upsert_offers (admin-only, called by sync edge function)
-- Inserts or updates offers from a provider's API response
-- =============================================================
CREATE OR REPLACE FUNCTION offer_admin_upsert_offers(
  p_provider_id uuid,
  p_offers jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_offer jsonb;
  v_count int := 0;
  v_existing_ids text[];
  v_fetched_ids text[];
  v_provider_slug text;
BEGIN
  -- This function is called by the offer-sync edge function with the service role key
  -- so is_admin() will not work. Instead, we check that the caller is NOT anon.
  -- The edge function uses the service role key which bypasses RLS.
  SELECT slug INTO v_provider_slug FROM offer_providers WHERE id = p_provider_id;
  IF v_provider_slug IS NULL THEN
    RETURN jsonb_build_object('error', 'Provider not found');
  END IF;

  -- Collect existing offer IDs for this provider
  SELECT array_agg(provider_offer_id) INTO v_existing_ids
  FROM offers WHERE provider_id = p_provider_id;

  -- Upsert each offer
  FOR v_offer IN SELECT * FROM jsonb_array_elements(p_offers)
  LOOP
    v_fetched_ids := array_append(v_fetched_ids, v_offer->>'provider_offer_id');

    INSERT INTO offers (
      provider_id, provider_offer_id, title, description, requirements,
      offer_type, reward, currency_code, icon_url, destination_url,
      platform, estimated_time_minutes, difficulty, category, active,
      updated_at
    ) VALUES (
      p_provider_id,
      v_offer->>'provider_offer_id',
      v_offer->>'title',
      COALESCE(v_offer->>'description', ''),
      COALESCE(v_offer->>'requirements', ''),
      COALESCE(v_offer->>'offer_type', 'other'),
      COALESCE((v_offer->>'reward')::numeric, 0),
      COALESCE(v_offer->>'currency_code', 'USD'),
      COALESCE(v_offer->>'icon_url', ''),
      COALESCE(v_offer->>'destination_url', ''),
      COALESCE(v_offer->>'platform', 'all'),
      COALESCE((v_offer->>'estimated_time_minutes')::int, 0),
      COALESCE(v_offer->>'difficulty', 'easy'),
      COALESCE(v_offer->>'category', ''),
      true,
      now()
    )
    ON CONFLICT (provider_id, provider_offer_id) DO UPDATE SET
      title = EXCLUDED.title,
      description = EXCLUDED.description,
      requirements = EXCLUDED.requirements,
      offer_type = EXCLUDED.offer_type,
      reward = EXCLUDED.reward,
      currency_code = EXCLUDED.currency_code,
      icon_url = EXCLUDED.icon_url,
      destination_url = EXCLUDED.destination_url,
      platform = EXCLUDED.platform,
      estimated_time_minutes = EXCLUDED.estimated_time_minutes,
      difficulty = EXCLUDED.difficulty,
      category = EXCLUDED.category,
      active = true,
      updated_at = now();

    v_count := v_count + 1;
  END LOOP;

  -- Deactivate offers that were not in the fresh fetch
  UPDATE offers SET active = false, updated_at = now()
  WHERE provider_id = p_provider_id
    AND active = true
    AND provider_offer_id <> ALL(COALESCE(v_fetched_ids, ARRAY[''::text]));

  -- Update last_synced_at
  UPDATE offer_providers SET last_synced_at = now() WHERE id = p_provider_id;

  RETURN jsonb_build_object(
    'ok', true,
    'synced', v_count,
    'deactivated', (SELECT count(*) FROM offers WHERE provider_id = p_provider_id AND active = false)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_admin_upsert_offers(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_admin_upsert_offers(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_admin_upsert_offers(uuid, jsonb) FROM authenticated;

-- =============================================================
-- Fix 4 & 5: Replace offer_process_conversion with currency + sanity checks
-- =============================================================
CREATE OR REPLACE FUNCTION offer_process_conversion(
  p_provider_slug text,
  p_tracking_id text,
  p_conversion_id text,
  p_reward numeric,
  p_revenue numeric DEFAULT 0,
  p_event_type text DEFAULT 'conversion',
  p_raw jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
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
  v_conversion_exists boolean;
  v_ref text;
  v_payload_currency text;
  v_max_reward_mult numeric := 5.0;
BEGIN
  -- Validate provider
  SELECT * INTO v_provider FROM offer_providers WHERE slug = p_provider_slug AND enabled = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Provider not found or disabled');
  END IF;

  -- Find session by tracking_id
  SELECT * INTO v_session FROM offer_sessions WHERE tracking_id = p_tracking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Session not found for tracking_id');
  END IF;

  -- Check for duplicate conversion (idempotency)
  SELECT EXISTS(
    SELECT 1 FROM offer_conversions
    WHERE provider_id = v_provider.id
      AND provider_conversion_id = p_conversion_id
      AND event_type = p_event_type
  ) INTO v_conversion_exists;

  IF v_conversion_exists THEN
    -- Record as duplicate for audit, but don't credit
    INSERT INTO offer_conversions (
      session_id, user_id, provider_id, provider_conversion_id,
      event_type, reward, revenue, status, raw_payload
    ) VALUES (
      v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
      p_event_type, p_reward, p_revenue, 'duplicate', p_raw
    ) ON CONFLICT (provider_id, provider_conversion_id, event_type) DO NOTHING;

    RETURN jsonb_build_object('status', 'duplicate', 'reason', 'Conversion already processed');
  END IF;

  -- Calculate final reward with provider margin
  v_final_reward := p_reward * (v_provider.reward_margin_percent / 100.0);

  -- Fix 5: Sanity bounds for conversion events
  IF p_event_type = 'conversion' THEN
    -- Reject if reward <= 0
    IF p_reward <= 0 THEN
      INSERT INTO offer_conversions (
        session_id, user_id, provider_id, provider_conversion_id,
        event_type, reward, revenue, status, raw_payload
      ) VALUES (
        v_session.id, v_session.user_id, v_provider.id, p_conversion_id,
        p_event_type, p_reward, p_revenue, 'rejected', p_raw
      ) ON CONFLICT DO NOTHING;
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'Reward must be greater than zero');
    END IF;

    -- Reject if provider margin is outside 0-200%
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

    -- Reject if final reward exceeds 5x the session's original snapshot reward
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
  END IF;

  -- Fix 4: Currency validation
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
    -- Don't process if session is already completed or reversed
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

    -- Lock profile for balance update
    SELECT * INTO v_profile FROM profiles WHERE id = v_session.user_id FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'User profile not found');
    END IF;

    -- Create idempotent ledger entry
    v_ref := 'offer:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reward', v_final_reward,
      'offer_session', v_session.id::text, v_ref,
      'Offer Reward — ' || v_session.provider_slug, 'completed'
    ) ON CONFLICT (reference) DO NOTHING RETURNING id INTO v_tx_id;

    -- Only credit balance if the transaction was actually inserted (not a duplicate)
    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
      SET available_balance = available_balance + v_final_reward,
          total_earned = total_earned + v_final_reward
      WHERE id = v_session.user_id;
    END IF;

    -- Update session
    UPDATE offer_sessions
    SET status = 'completed',
        completed_at = now(),
        provider_conversion_id = p_conversion_id,
        revenue = p_revenue
    WHERE id = v_session.id;

    -- Record conversion
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
      'reward', v_final_reward,
      'transaction_id', v_tx_id
    );

  ELSIF p_event_type = 'reversal' THEN
    -- Reversal: debit the balance, mark session reversed
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

    v_ref := 'offer_reversal:' || v_session.id::text;
    INSERT INTO transactions (
      user_id, type, amount, reference_type, reference_id, reference, description, status
    ) VALUES (
      v_session.user_id, 'offer_reversal', -v_final_reward,
      'offer_session', v_session.id::text, v_ref,
      'Offer Reversal — ' || v_session.provider_slug, 'reversed'
    ) ON CONFLICT (reference) DO NOTHING RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
      SET available_balance = available_balance - v_final_reward,
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
      'reversed_reward', v_final_reward,
      'transaction_id', v_tx_id
    );

  ELSE
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'Unknown event type');
  END IF;
END;
$$;

-- CRITICAL: Do NOT grant to anon or authenticated — service role only
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM authenticated;

-- =============================================================
-- Update offer_admin_list_providers to include last_synced_at
-- =============================================================
CREATE OR REPLACE FUNCTION offer_admin_list_providers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
BEGIN
  SELECT is_admin() INTO v_is_admin;
  IF NOT v_is_admin THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id,
      'slug', p.slug,
      'display_name', p.display_name,
      'provider_type', p.provider_type,
      'enabled', p.enabled,
      'has_api_key', p.api_key_encrypted IS NOT NULL,
      'has_postback_secret', p.postback_secret_encrypted IS NOT NULL,
      'publisher_id', p.publisher_id,
      'postback_url', p.postback_url,
      'currency_code', p.currency_code,
      'reward_margin_percent', p.reward_margin_percent,
      'config', p.config,
      'last_synced_at', p.last_synced_at,
      'created_at', p.created_at
    ) ORDER BY p.created_at)
    FROM offer_providers p
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION offer_admin_list_providers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION offer_admin_list_providers() TO authenticated;
