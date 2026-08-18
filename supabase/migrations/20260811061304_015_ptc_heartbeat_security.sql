/*
# PTC Heartbeat & Active-Time Security Hardening

1. Schema Changes
- `ptc_ad_views`: add `active_seconds` (int, default 0) — server-accumulated active viewing time.
- `ptc_ad_views`: add `last_heartbeat_at` (timestamptz, nullable) — timestamp of last heartbeat.
- `ptc_ad_views`: add `session_token` (uuid, default gen_random_uuid()) — per-session token to
  bind heartbeats and claims to the originating tab. Prevents cross-tab replay.
- `ptc_ad_views`: add `expires_at` (timestamptz, nullable) — when the view session expires if
  no heartbeat arrives. Set to started_at + required_duration + 120s grace.

2. New Function: `ptc_heartbeat(p_view_id, p_session_token)`
- SECURITY DEFINER. Called by the frontend every ~5 seconds during active viewing.
- Validates: view exists, belongs to auth.uid(), status = 'pending', session_token matches.
- Calculates real elapsed time since last_heartbeat (capped at 15s to prevent forged durations).
- Accumulates into `active_seconds`. Updates `last_heartbeat_at`.
- Returns current accumulated active_seconds and remaining time.
- If the view session has expired (now > expires_at AND active_seconds < required_duration),
  marks status = 'expired' and returns an error.

3. Modified Function: `ptc_start(p_ad_id)`
- Now also checks for any existing 'pending' view session for this user today. If one exists
  for a DIFFERENT ad, it gets cancelled (only one active session at a time). If one exists for
  the SAME ad, the daily limit check already prevents a new one.
- Returns `session_token` alongside the existing fields.

4. Modified Function: `ptc_claim(p_view_id)`
- Now validates `active_seconds >= required_duration` INSTEAD of wall-clock elapsed time.
  This means the user must have sent heartbeats accumulating real active time. A user who
  opens a tab, walks away, and comes back after the wall-clock duration will NOT have enough
  active_seconds because no heartbeats were sent.
- Still uses SELECT FOR UPDATE + unique transaction reference for atomicity.
- Still re-validates ad active, limits, ownership.
- The `session_token` is NOT required for claim (the view_id + ownership is sufficient),
  but active_seconds must be sufficient.

5. Security
- All functions SECURITY DEFINER, SET search_path = public.
- REVOKE EXECUTE FROM anon, GRANT TO authenticated.
- Actor always from auth.uid(), never a parameter.
- No client-supplied active_seconds, reward, user_id, or ad_id is trusted.
- Heartbeat interval is server-enforced: elapsed time since last heartbeat is capped at 15s
  (heartbeats sent less frequently only count 15s of active time, not the full gap).
- This prevents "modified JavaScript timers" and "forged heartbeat durations" because the
  server independently measures time between heartbeats.

6. Notes
- The frontend timer remains purely visual. The server's active_seconds is authoritative.
- Duplicate tabs: each tab gets its own session_token from ptc_start. A second ptc_start for
  the same ad on the same day is blocked by the daily view limit. A second ptc_start for a
  different ad cancels the first pending session.
- Duplicate claims: prevented by status check + unique transaction reference.
- Replayed requests: a completed view cannot be claimed again (status = 'completed' check).
- Manually forged completion requests: active_seconds is server-accumulated from heartbeats;
  a forged claim with insufficient active_seconds is rejected.
*/

-- Add columns to ptc_ad_views
ALTER TABLE ptc_ad_views
  ADD COLUMN IF NOT EXISTS active_seconds integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS session_token uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- ---------- ptc_start (updated) ----------
CREATE OR REPLACE FUNCTION ptc_start(p_ad_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ad ptc_ads%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_view ptc_ad_views%ROWTYPE;
  v_today_count integer;
  v_existing ptc_ad_views%ROWTYPE;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  -- Cancel any existing pending view session for this user (different ad)
  -- This enforces one active session at a time (duplicate tab prevention)
  SELECT * INTO v_existing FROM ptc_ad_views
    WHERE user_id = auth.uid() AND status = 'pending'
    AND ptc_ad_id != p_ad_id
    FOR UPDATE;
  IF FOUND THEN
    UPDATE ptc_ad_views SET status = 'cancelled' WHERE id = v_existing.id;
  END IF;

  SELECT * INTO v_ad FROM ptc_ads WHERE id = p_ad_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;
  IF NOT v_ad.active THEN RAISE EXCEPTION 'Advertisement is not active'; END IF;
  IF v_ad.start_date IS NOT NULL AND now() < v_ad.start_date THEN RAISE EXCEPTION 'Advertisement not yet available'; END IF;
  IF v_ad.end_date IS NOT NULL AND now() > v_ad.end_date THEN RAISE EXCEPTION 'Advertisement has expired'; END IF;
  IF v_ad.total_view_limit > 0 AND v_ad.total_views >= v_ad.total_view_limit THEN
    RAISE EXCEPTION 'Total view limit reached for this advertisement';
  END IF;

  -- Check today's views by this user for this ad (pending or completed)
  SELECT count(*) INTO v_today_count FROM ptc_ad_views
    WHERE user_id = auth.uid() AND ptc_ad_id = p_ad_id AND view_date = current_date
      AND status IN ('pending','completed');
  IF v_today_count >= v_ad.daily_view_limit THEN
    RAISE EXCEPTION 'Daily view limit reached for this advertisement';
  END IF;

  -- Create view session with expiry
  INSERT INTO ptc_ad_views (user_id, ptc_ad_id, required_duration, reward, status, started_at, view_date,
    expires_at, last_heartbeat_at)
    VALUES (auth.uid(), p_ad_id, v_ad.duration_seconds, v_ad.reward, 'pending', now(), current_date,
      now() + (v_ad.duration_seconds + 120) * interval '1 second', now())
    RETURNING * INTO v_view;

  RETURN jsonb_build_object(
    'view_id', v_view.id,
    'started_at', v_view.started_at,
    'required_duration', v_view.required_duration,
    'reward', v_view.reward,
    'status', v_view.status,
    'session_token', v_view.session_token
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_start(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_start(uuid) TO authenticated;

-- ---------- ptc_heartbeat (new) ----------
CREATE OR REPLACE FUNCTION ptc_heartbeat(p_view_id uuid, p_session_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_view ptc_ad_views%ROWTYPE;
  v_elapsed_since_last integer;
  v_remaining integer;
BEGIN
  SELECT * INTO v_view FROM ptc_ad_views WHERE id = p_view_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'View session not found'; END IF;
  IF v_view.user_id != auth.uid() THEN RAISE EXCEPTION 'View does not belong to you'; END IF;
  IF v_view.status != 'pending' THEN RAISE EXCEPTION 'View session is no longer active'; END IF;
  IF v_view.session_token != p_session_token THEN RAISE EXCEPTION 'Invalid session token'; END IF;

  -- Check if session has expired
  IF now() > v_view.expires_at AND v_view.active_seconds < v_view.required_duration THEN
    UPDATE ptc_ad_views SET status = 'expired' WHERE id = p_view_id;
    RAISE EXCEPTION 'View session expired due to inactivity';
  END IF;

  -- Calculate real elapsed time since last heartbeat, capped at 15 seconds
  -- This prevents forged long durations: even if the client waits 60s between
  -- heartbeats, only 15s of active time is credited.
  v_elapsed_since_last := LEAST(15, extract(epoch from (now() - COALESCE(v_view.last_heartbeat_at, v_view.started_at)))::integer);

  -- Accumulate active time
  v_view.active_seconds := v_view.active_seconds + v_elapsed_since_last;

  -- Update the view row
  UPDATE ptc_ad_views
    SET active_seconds = v_view.active_seconds,
        last_heartbeat_at = now()
    WHERE id = p_view_id;

  v_remaining := GREATEST(0, v_view.required_duration - v_view.active_seconds);

  RETURN jsonb_build_object(
    'ok', true,
    'active_seconds', v_view.active_seconds,
    'required_duration', v_view.required_duration,
    'remaining', v_remaining
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_heartbeat(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_heartbeat(uuid, uuid) TO authenticated;

-- ---------- ptc_claim (updated) ----------
CREATE OR REPLACE FUNCTION ptc_claim(p_view_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_view ptc_ad_views%ROWTYPE;
  v_ad ptc_ads%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  -- Lock the view row to serialize concurrent claims
  SELECT * INTO v_view FROM ptc_ad_views WHERE id = p_view_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'View session not found'; END IF;
  IF v_view.user_id != auth.uid() THEN RAISE EXCEPTION 'View does not belong to you'; END IF;
  IF v_view.status = 'completed' THEN RAISE EXCEPTION 'Reward already claimed'; END IF;
  IF v_view.status = 'expired' OR v_view.status = 'cancelled' THEN RAISE EXCEPTION 'View session is no longer valid'; END IF;

  -- SERVER-SIDE active time check — the ONLY timer that matters
  -- The displayed browser timer is NEVER authoritative. We check accumulated
  -- active_seconds from heartbeats, NOT wall-clock elapsed time.
  IF v_view.active_seconds < v_view.required_duration THEN
    RAISE EXCEPTION 'Active viewing time not yet satisfied (active %, required %)',
      v_view.active_seconds, v_view.required_duration;
  END IF;

  -- Re-validate ad is still active and within limits
  SELECT * INTO v_ad FROM ptc_ads WHERE id = v_view.ptc_ad_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;
  IF NOT v_ad.active THEN RAISE EXCEPTION 'Advertisement is no longer active'; END IF;
  IF v_ad.end_date IS NOT NULL AND now() > v_ad.end_date THEN RAISE EXCEPTION 'Advertisement has expired'; END IF;
  IF v_ad.total_view_limit > 0 AND v_ad.total_views >= v_ad.total_view_limit THEN
    RAISE EXCEPTION 'Total view limit reached for this advertisement';
  END IF;

  v_ref := 'ptc:' || v_view.id::text;

  -- Atomic transaction: mark completed, ledger entry, balances, counters
  UPDATE ptc_ad_views SET status = 'completed', completed_at = now() WHERE id = p_view_id;

  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ptc_reward', v_view.reward, 'ptc_ad_view', v_view.id, v_ref, 'PTC advertisement reward', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NULL THEN
    -- Another claim already landed; ensure view marked completed and exit cleanly
    RETURN jsonb_build_object('ok', true, 'already_claimed', true, 'reward', v_view.reward);
  END IF;

  UPDATE profiles
    SET available_balance = available_balance + v_view.reward,
        total_earned = total_earned + v_view.reward,
        ptc_views = ptc_views + 1
    WHERE id = auth.uid();

  UPDATE ptc_ads SET total_views = total_views + 1 WHERE id = v_ad.id;

  RETURN jsonb_build_object(
    'ok', true,
    'reward', v_view.reward,
    'transaction_id', v_tx_id,
    'completed_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_claim(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_claim(uuid) TO authenticated;
