/*
# PTC + task server-side functions

1. Functions
- `is_admin()` / `is_staff_or_admin()` — helper checks using auth.uid() (never a parameter).
- `ptc_start(p_ad_id)` — creates a view session for the authenticated user. Validates ad
  exists, is active, is within schedule, daily/total limits not reached, user not already
  viewing today. Returns the view row with started_at and required_duration. The frontend
  timer is purely visual; the server records started_at.
- `ptc_claim(p_view_id)` — the authoritative reward path. Locks the view row FOR UPDATE,
  verifies ownership, verifies SERVER TIME elapsed >= required_duration since started_at,
  checks reward not already issued, then atomically: marks view completed, inserts a ledger
  transaction with a unique reference (idempotency guard), increments profile balances and
  ptc_views, increments ad total_views. All in one transaction. Returns the reward.
- `task_submit(p_task_id, p_proof_text)` — creates a task completion (status pending or
  approved depending on proof_required). Unique constraint prevents duplicate. If auto-
  approve (no proof required), reward is credited atomically. Otherwise pending for admin.

2. Security
- All functions SECURITY DEFINER, SET search_path = public, REVOKE EXECUTE FROM anon,
  GRANT EXECUTE TO authenticated.
- Actor is always derived from auth.uid(), never a parameter.
- No client-supplied amount is trusted; reward is read from the ad/task row.

3. Notes
- ptc_claim uses SELECT FOR UPDATE on the view row to serialize concurrent claims.
- The unique `reference` on transactions prevents any duplicate reward even if the view
  status check races.
- Server time (now()) is the only timer that matters.
*/

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin');
$$;

CREATE OR REPLACE FUNCTION is_staff_or_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','moderator'));
$$;

-- ---------- ptc_start ----------
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
  v_ref text;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_ad FROM ptc_ads WHERE id = p_ad_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;
  IF NOT v_ad.active THEN RAISE EXCEPTION 'Advertisement is not active'; END IF;
  IF v_ad.start_date IS NOT NULL AND now() < v_ad.start_date THEN RAISE EXCEPTION 'Advertisement not yet available'; END IF;
  IF v_ad.end_date IS NOT NULL AND now() > v_ad.end_date THEN RAISE EXCEPTION 'Advertisement has expired'; END IF;
  IF v_ad.total_view_limit > 0 AND v_ad.total_views >= v_ad.total_view_limit THEN
    RAISE EXCEPTION 'Total view limit reached for this advertisement';
  END IF;

  -- Check today's views by this user for this ad
  SELECT count(*) INTO v_today_count FROM ptc_ad_views
    WHERE user_id = auth.uid() AND ptc_ad_id = p_ad_id AND view_date = current_date
      AND status IN ('pending','completed');
  IF v_today_count >= v_ad.daily_view_limit THEN
    RAISE EXCEPTION 'Daily view limit reached for this advertisement';
  END IF;

  -- Create view session
  INSERT INTO ptc_ad_views (user_id, ptc_ad_id, required_duration, reward, status, started_at, view_date)
    VALUES (auth.uid(), p_ad_id, v_ad.duration_seconds, v_ad.reward, 'pending', now(), current_date)
    RETURNING * INTO v_view;

  RETURN jsonb_build_object(
    'view_id', v_view.id,
    'started_at', v_view.started_at,
    'required_duration', v_view.required_duration,
    'reward', v_view.reward,
    'status', v_view.status
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_start(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_start(uuid) TO authenticated;

-- ---------- ptc_claim ----------
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
  v_elapsed numeric;
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

  -- SERVER TIME check — the only timer that matters
  v_elapsed := extract(epoch from (now() - v_view.started_at));
  IF v_elapsed < v_view.required_duration THEN
    RAISE EXCEPTION 'View duration not yet satisfied (elapsed %, required %)', v_elapsed, v_view.required_duration;
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

-- ---------- task_submit ----------
CREATE OR REPLACE FUNCTION task_submit(p_task_id uuid, p_proof_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_today_count integer;
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

  -- daily limit check
  IF v_task.daily_limit > 0 THEN
    SELECT count(*) INTO v_today_count FROM task_completions
      WHERE user_id = auth.uid() AND task_id = p_task_id
        AND date_trunc('day', created_at) = current_date;
    IF v_today_count >= v_task.daily_limit THEN RAISE EXCEPTION 'Daily limit reached for this task'; END IF;
  END IF;

  -- Insert completion; unique(user_id, task_id) prevents duplicates
  INSERT INTO task_completions (user_id, task_id, proof_text, reward, status)
    VALUES (auth.uid(), p_task_id, COALESCE(p_proof_text, ''), v_task.reward,
      CASE WHEN v_task.proof_required THEN 'pending' ELSE 'approved' END)
    ON CONFLICT (user_id, task_id) DO NOTHING
    RETURNING * INTO v_completion;

  IF v_completion IS NULL THEN
    RAISE EXCEPTION 'You have already submitted this task';
  END IF;

  UPDATE tasks SET total_completions = total_completions + 1 WHERE id = p_task_id;

  -- Auto-approve + reward if no proof required
  IF NOT v_task.proof_required THEN
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
      VALUES (auth.uid(), 'task_reward', v_task.reward, 'task_completion', v_completion.id, v_ref, 'Task reward', 'completed')
      ON CONFLICT (reference) DO NOTHING
      RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET available_balance = available_balance + v_task.reward,
            total_earned = total_earned + v_task.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = auth.uid();
    END IF;
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'reward', v_task.reward, 'completion_id', v_completion.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'pending', 'completion_id', v_completion.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;
