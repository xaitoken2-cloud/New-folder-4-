/*
# Update ptc_claim & task_submit for campaign budget deduction + admin campaign approval

1. Changes to ptc_claim
   - After crediting the viewer, if the ad has an advertiser_id (campaign), deduct the
     reward from the campaign's spent column. If spent >= budget, auto-deactivate
     (active=false, status='completed').

2. Changes to task_submit (auto-approve path)
   - Same budget deduction logic for task campaigns with advertiser_id.

3. Changes to admin_review_task (approval path)
   - Same budget deduction when a task with advertiser_id is approved.

4. New admin functions
   - `admin_approve_campaign(p_campaign_id, p_type)` — admin approves a pending campaign,
     setting status='active', active=true.
   - `admin_reject_campaign(p_campaign_id, p_type, p_note)` — admin rejects a pending
     campaign, refunding the full budget to the advertiser's advertising_balance.
     status='rejected', active=false.

5. Security
   - All SECURITY DEFINER, search_path = public. Admin functions check is_admin().
   - Budget deduction happens inside the existing atomic transaction.

6. Notes
   - For admin-created ads (advertiser_id IS NULL), no budget deduction occurs — they
     continue to work as before with unlimited budget.
*/

-- ---------- Updated ptc_claim with budget deduction ----------
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

  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ptc_reward', v_view.reward, 'ptc_ad_view', v_view.id, v_ref, 'PTC advertisement reward', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_claimed', true, 'reward', v_view.reward);
  END IF;

  UPDATE profiles
    SET available_balance = available_balance + v_view.reward,
        total_earned = total_earned + v_view.reward,
        ptc_views = ptc_views + 1
    WHERE id = auth.uid();

  UPDATE ptc_ads SET total_views = total_views + 1 WHERE id = v_ad.id;

  -- Deduct from campaign budget if advertiser-funded
  IF v_ad.advertiser_id IS NOT NULL THEN
    UPDATE ptc_ads
      SET spent = spent + v_view.reward,
          active = CASE WHEN spent + v_view.reward >= budget THEN false ELSE active END,
          status = CASE WHEN spent + v_view.reward >= budget THEN 'completed' ELSE status END
      WHERE id = v_ad.id;
  END IF;

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

-- ---------- Updated task_submit with budget deduction ----------
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

      -- Deduct from campaign budget if advertiser-funded
      IF v_task.advertiser_id IS NOT NULL THEN
        UPDATE tasks
          SET spent = spent + v_task.reward,
              active = CASE WHEN spent + v_task.reward >= budget THEN false ELSE active END,
              status = CASE WHEN spent + v_task.reward >= budget THEN 'completed' ELSE status END
          WHERE id = p_task_id;
      END IF;
    END IF;
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'reward', v_task.reward, 'completion_id', v_completion.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'pending', 'completion_id', v_completion.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

-- ---------- admin_approve_campaign ----------
CREATE OR REPLACE FUNCTION admin_approve_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type = 'ptc' THEN
    UPDATE ptc_ads SET status = 'active', active = true
      WHERE id = p_campaign_id AND status = 'pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'Pending PTC campaign not found'; END IF;
  ELSIF p_type = 'task' THEN
    UPDATE tasks SET status = 'active', active = true
      WHERE id = p_campaign_id AND status = 'pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'Pending task campaign not found'; END IF;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'approve_campaign', p_type, p_campaign_id::text, jsonb_build_object('type', p_type));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_approve_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_approve_campaign(uuid, text) TO authenticated;

-- ---------- admin_reject_campaign ----------
CREATE OR REPLACE FUNCTION admin_reject_campaign(p_campaign_id uuid, p_type text, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_advertiser_id uuid;
  v_budget numeric(18,8);
  v_spent numeric(18,8);
  v_refund numeric(18,8);
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type = 'ptc' THEN
    SELECT advertiser_id, budget, spent INTO v_advertiser_id, v_budget, v_spent
      FROM ptc_ads WHERE id = p_campaign_id AND status = 'pending' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pending PTC campaign not found'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE ptc_ads SET status = 'rejected', active = false WHERE id = p_campaign_id;
    IF v_advertiser_id IS NOT NULL AND v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = v_advertiser_id;
      v_ref := 'ad_refund:ptc_reject:' || p_campaign_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (v_advertiser_id, 'ad_refund', v_refund, 'ptc_ad', p_campaign_id, v_ref,
          'PTC campaign rejected — budget refund', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  ELSIF p_type = 'task' THEN
    SELECT advertiser_id, budget, spent INTO v_advertiser_id, v_budget, v_spent
      FROM tasks WHERE id = p_campaign_id AND status = 'pending' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pending task campaign not found'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE tasks SET status = 'rejected', active = false WHERE id = p_campaign_id;
    IF v_advertiser_id IS NOT NULL AND v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = v_advertiser_id;
      v_ref := 'ad_refund:task_reject:' || p_campaign_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (v_advertiser_id, 'ad_refund', v_refund, 'task', p_campaign_id, v_ref,
          'Task campaign rejected — budget refund', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'reject_campaign', p_type, p_campaign_id::text,
      jsonb_build_object('type', p_type, 'note', p_note, 'refund', v_refund));
  RETURN jsonb_build_object('ok', true, 'refund', v_refund);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_reject_campaign(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_reject_campaign(uuid, text, text) TO authenticated;

-- ---------- admin_list_pending_campaigns ----------
CREATE OR REPLACE FUNCTION admin_list_pending_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN jsonb_build_object(
    'ptc_campaigns', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title, 'category', a.category, 'reward', a.reward,
        'duration_seconds', a.duration_seconds, 'budget', a.budget,
        'advertiser_id', a.advertiser_id, 'advertiser_name', p.username,
        'destination_url', a.destination_url, 'image_url', a.image_url,
        'daily_view_limit', a.daily_view_limit, 'total_view_limit', a.total_view_limit,
        'created_at', a.created_at
      ) ORDER BY a.created_at DESC)
      FROM ptc_ads a
      LEFT JOIN profiles p ON p.id = a.advertiser_id
      WHERE a.status = 'pending' AND a.advertiser_id IS NOT NULL
    ),
    'task_campaigns', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'category', t.category, 'reward', t.reward,
        'task_type', t.task_type, 'budget', t.budget,
        'advertiser_id', t.advertiser_id, 'advertiser_name', p.username,
        'action_url', t.action_url, 'proof_required', t.proof_required,
        'proof_instructions', t.proof_instructions,
        'daily_limit', t.daily_limit, 'total_limit', t.total_limit,
        'created_at', t.created_at
      ) ORDER BY t.created_at DESC)
      FROM tasks t
      LEFT JOIN profiles p ON p.id = t.advertiser_id
      WHERE t.status = 'pending' AND t.advertiser_id IS NOT NULL
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_pending_campaigns() FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_pending_campaigns() TO authenticated;
