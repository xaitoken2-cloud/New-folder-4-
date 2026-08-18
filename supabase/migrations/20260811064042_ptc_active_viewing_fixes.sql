/*
# PTC Active-Viewing Fixes

1. ptc_start: Expire stale pending sessions (past expires_at) before the daily
   limit check, freeing up daily limit slots when users abandon sessions. Also
   cancel ALL pending sessions (not just different-ad ones) to enforce one
   active session at a time — opening the same ad in a second tab cancels the
   first tab's session.

2. ptc_heartbeat: Reduce elapsed-time cap from 15s to 8s. With a 5s heartbeat
   interval, 8s provides 3s margin for network latency while limiting unearned
   credit when a user switches tabs and returns. Combined with the frontend
   visibility check (heartbeats only fire when the tab is visible and focused),
   this ensures active time pauses when the user leaves and resumes when they
   return.

3. ptc_claim: No changes — active_seconds check is already server-authoritative.
*/

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

  -- Expire stale pending sessions (past expires_at) for this user
  UPDATE ptc_ad_views SET status = 'expired'
    WHERE user_id = auth.uid() AND status = 'pending'
    AND expires_at IS NOT NULL AND now() > expires_at;

  -- Cancel any existing pending view session for this user (any ad).
  -- This enforces one active session at a time — opening the same ad in a
  -- second tab cancels the first tab's session (its heartbeats will fail).
  SELECT * INTO v_existing FROM ptc_ad_views
    WHERE user_id = auth.uid() AND status = 'pending'
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

-- ---------- ptc_heartbeat (updated) ----------
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
  IF v_view.expires_at IS NOT NULL AND now() > v_view.expires_at AND v_view.active_seconds < v_view.required_duration THEN
    UPDATE ptc_ad_views SET status = 'expired' WHERE id = p_view_id;
    RAISE EXCEPTION 'View session expired due to inactivity';
  END IF;

  -- Calculate real elapsed time since last heartbeat, capped at 8 seconds.
  -- With 5s heartbeat interval, 8s gives 3s margin for network latency.
  -- When a user switches tabs, the frontend stops sending heartbeats (visibility
  -- check). On return, the gap is capped at 8s, limiting unearned active time.
  v_elapsed_since_last := LEAST(8, extract(epoch from (now() - COALESCE(v_view.last_heartbeat_at, v_view.started_at)))::integer);

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