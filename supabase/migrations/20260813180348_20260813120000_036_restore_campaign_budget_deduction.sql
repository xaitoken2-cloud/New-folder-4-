/*
# Restore campaign budget deduction logic
1. Bug
- ptc_claim(), task_submit(), and admin_review_task() credit rewards and
  referral commissions but never deduct from the advertiser's campaign
  budget (spent/budget on ptc_ads / tasks). Advertiser-funded campaigns
  therefore never mark themselves completed when the budget is exhausted.
2. Fix
- Add the spent/budget UPDATE block to each function, right after the
  reward is credited and before referral commissions are paid. The base
  USD reward (v_view.reward / v_task.reward / v_completion.reward) is used
  because budget/spent are USD-denominated and unaffected by the XC
  multiplier. Only advertiser-funded rows (advertiser_id IS NOT NULL) are
  touched.
*/
CREATE OR REPLACE FUNCTION public.ptc_claim(p_view_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

IF v_ad.advertiser_id IS NOT NULL THEN
  UPDATE ptc_ads
    SET spent = spent + v_view.reward,
        active = CASE WHEN spent + v_view.reward >= budget THEN false ELSE active END,
        status = CASE WHEN spent + v_view.reward >= budget THEN 'completed' ELSE status END
  WHERE id = v_ad.id;
END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.task_submit(p_task_id uuid, p_proof_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
IF v_task.advertiser_id IS NOT NULL THEN
  UPDATE tasks
    SET spent = spent + v_task.reward,
        active = CASE WHEN spent + v_task.reward >= budget THEN false ELSE active END,
        status = CASE WHEN spent + v_task.reward >= budget THEN 'completed' ELSE status END
  WHERE id = p_task_id;
END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.admin_review_task(p_completion_id uuid, p_approve boolean, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
v_completion task_completions%ROWTYPE;
v_task tasks%ROWTYPE;
v_ref text;
v_tx_id uuid;
v_xc_reward numeric(18,8);
v_multiplier numeric(18,8);
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
SELECT * INTO v_completion FROM task_completions WHERE id = p_completion_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'Task completion not found'; END IF;
IF v_completion.status != 'pending' THEN RAISE EXCEPTION 'Task already reviewed'; END IF;
SELECT * INTO v_task FROM tasks WHERE id = v_completion.task_id FOR UPDATE;

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
IF v_task.advertiser_id IS NOT NULL THEN
  UPDATE tasks
    SET spent = spent + v_completion.reward,
        active = CASE WHEN spent + v_completion.reward >= budget THEN false ELSE active END,
        status = CASE WHEN spent + v_completion.reward >= budget THEN 'completed' ELSE status END
  WHERE id = v_task.id;
END IF;
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
$function$;