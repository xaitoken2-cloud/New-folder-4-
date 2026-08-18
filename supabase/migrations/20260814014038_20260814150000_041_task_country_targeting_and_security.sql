/*
# Task Country Targeting + Anti-Fraud Security

1. Purpose
   Replicate the PTC country-targeting architecture (migration 039) for task campaigns.
   Also adds a self-completion guard to task_submit (advertiser cannot complete own task).

2. Schema Changes
   - tasks: add `target_all_countries boolean NOT NULL DEFAULT true`
   - New table `task_countries` mirroring ptc_ad_countries.

3. Function Changes
   - ad_create_task_campaign: DROP old signature, CREATE new with p_target_countries.
   - task_submit: add country + self-completion guards (full body from 036 + new blocks).
   - ad_list_campaigns, admin_list_pending_campaigns, admin_list_all_campaigns:
     add target_all_countries + target_countries to task_campaigns.
*/
-- 1. tasks.target_all_countries column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS target_all_countries boolean NOT NULL DEFAULT true;

-- 2. task_countries table
CREATE TABLE IF NOT EXISTS task_countries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  country_code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, country_code)
);
CREATE INDEX IF NOT EXISTS task_countries_task_id_idx ON task_countries (task_id);
ALTER TABLE task_countries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'task_countries' AND policyname = 'task_countries_select_authenticated'
  ) THEN
    CREATE POLICY "task_countries_select_authenticated" ON task_countries FOR SELECT
      TO authenticated USING (true);
  END IF;
END $$;

-- 3. Drop old ad_create_task_campaign and recreate with targeting param
DROP FUNCTION IF EXISTS ad_create_task_campaign(text, text, text, text, text, numeric, text, boolean, text, integer, integer, numeric);

CREATE OR REPLACE FUNCTION public.ad_create_task_campaign(
  p_title text, p_description text, p_instructions text, p_category text,
  p_task_type text, p_reward numeric, p_action_url text,
  p_proof_required boolean, p_proof_instructions text,
  p_daily_limit integer, p_total_limit integer, p_budget numeric,
  p_target_countries text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_profile profiles%ROWTYPE;
  v_task_id uuid;
  v_ref text;
  v_tx_id uuid;
  v_target_all boolean;
  v_code text;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  IF p_budget IS NULL OR p_budget <= 0 THEN RAISE EXCEPTION 'Invalid budget'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Invalid reward'; END IF;
  IF p_daily_limit IS NULL OR p_daily_limit < 0 THEN RAISE EXCEPTION 'Invalid daily limit'; END IF;
  IF p_total_limit IS NULL OR p_total_limit < 0 THEN RAISE EXCEPTION 'Invalid total limit'; END IF;
  IF p_budget > v_profile.advertising_balance THEN
    RAISE EXCEPTION 'Insufficient advertising balance'; END IF;

  v_target_all := (p_target_countries IS NULL OR array_length(p_target_countries, 1) IS NULL);

  UPDATE profiles SET advertising_balance = advertising_balance - p_budget WHERE id = auth.uid();

  INSERT INTO tasks (
    title, description, instructions, category, task_type, reward, action_url,
    proof_required, proof_instructions, daily_limit, total_limit,
    active, advertiser_id, budget, spent, status,
    target_all_countries
  ) VALUES (
    p_title, COALESCE(p_description, ''), COALESCE(p_instructions, ''),
    COALESCE(p_category, 'general'), COALESCE(p_task_type, 'custom'),
    p_reward, COALESCE(p_action_url, ''), COALESCE(p_proof_required, false),
    COALESCE(p_proof_instructions, ''), p_daily_limit, p_total_limit,
    false, auth.uid(), p_budget, 0, 'pending',
    v_target_all
  ) RETURNING id INTO v_task_id;

  IF NOT v_target_all THEN
    FOREACH v_code IN ARRAY p_target_countries LOOP
      v_code := upper(btrim(v_code));
      IF v_code <> '' THEN
        INSERT INTO task_countries (task_id, country_code) VALUES (v_task_id, v_code)
        ON CONFLICT (task_id, country_code) DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  v_ref := 'ad_spend:task:' || v_task_id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ad_spend', -p_budget, 'task', v_task_id, v_ref,
      'Task campaign budget allocation', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object('ok', true, 'campaign_id', v_task_id, 'status', 'pending');
END;
$function$;

REVOKE EXECUTE ON FUNCTION ad_create_task_campaign FROM anon;
GRANT EXECUTE ON FUNCTION ad_create_task_campaign TO authenticated;

-- 4. task_submit with country targeting + self-completion guard
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

-- Self-completion guard
IF v_task.advertiser_id IS NOT NULL AND v_task.advertiser_id = auth.uid() THEN
RAISE EXCEPTION 'You cannot complete your own task';
END IF;

-- Country targeting enforcement
IF NOT v_task.target_all_countries THEN
  IF v_profile.country IS NULL OR v_profile.country = '' THEN
    RAISE EXCEPTION 'This task is not available in your region';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM task_countries
    WHERE task_id = v_task.id AND upper(country_code) = upper(v_profile.country)
  ) THEN
    RAISE EXCEPTION 'This task is not available in your region';
  END IF;
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

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

-- 5. ad_list_campaigns with task targeting fields
CREATE OR REPLACE FUNCTION public.ad_list_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

RETURN jsonb_build_object(
'ptc_campaigns', (
SELECT jsonb_agg(jsonb_build_object(
'id', a.id, 'title', a.title, 'category', a.category, 'reward', a.reward,
'duration_seconds', a.duration_seconds, 'budget', a.budget, 'spent', a.spent,
'status', a.status, 'active', a.active, 'total_views', a.total_views,
'daily_view_limit', a.daily_view_limit, 'total_view_limit', a.total_view_limit,
'target_all_countries', a.target_all_countries,
'target_devices', a.target_devices,
'target_countries', COALESCE((SELECT jsonb_agg(country_code) FROM ptc_ad_countries WHERE ptc_ad_id = a.id), '[]'::jsonb),
'created_at', a.created_at
) ORDER BY a.created_at DESC)
FROM ptc_ads a WHERE a.advertiser_id = auth.uid()
),
'task_campaigns', (
SELECT jsonb_agg(jsonb_build_object(
'id', t.id, 'title', t.title, 'category', t.category, 'reward', t.reward,
'task_type', t.task_type, 'budget', t.budget, 'spent', t.spent,
'status', t.status, 'active', t.active, 'total_completions', t.total_completions,
'daily_limit', t.daily_limit, 'total_limit', t.total_limit,
'target_all_countries', t.target_all_countries,
'target_countries', COALESCE((SELECT jsonb_agg(country_code) FROM task_countries WHERE task_id = t.id), '[]'::jsonb),
'created_at', t.created_at
) ORDER BY t.created_at DESC)
FROM tasks t WHERE t.advertiser_id = auth.uid()
)
);
END;
$function$;

REVOKE EXECUTE ON FUNCTION ad_list_campaigns() FROM anon;
GRANT EXECUTE ON FUNCTION ad_list_campaigns() TO authenticated;

-- 6. admin_list_pending_campaigns with task targeting fields
CREATE OR REPLACE FUNCTION public.admin_list_pending_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
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
'target_all_countries', a.target_all_countries,
'target_devices', a.target_devices,
'target_countries', COALESCE((SELECT jsonb_agg(c.country_code) FROM ptc_ad_countries c WHERE c.ptc_ad_id = a.id), '[]'::jsonb),
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
'target_all_countries', t.target_all_countries,
'target_countries', COALESCE((SELECT jsonb_agg(c.country_code) FROM task_countries c WHERE c.task_id = t.id), '[]'::jsonb),
'created_at', t.created_at
) ORDER BY t.created_at DESC)
FROM tasks t
LEFT JOIN profiles p ON p.id = t.advertiser_id
WHERE t.status = 'pending' AND t.advertiser_id IS NOT NULL
)
);
END;
$function$;

REVOKE EXECUTE ON FUNCTION admin_list_pending_campaigns() FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_pending_campaigns() TO authenticated;

-- 7. admin_list_all_campaigns with task targeting fields
CREATE OR REPLACE FUNCTION public.admin_list_all_campaigns(p_type text, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
v_ptc jsonb;
v_task jsonb;
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

IF p_type IS NULL OR p_type = 'ptc' THEN
SELECT COALESCE(jsonb_agg(jsonb_build_object(
'id', a.id, 'title', a.title, 'category', a.category, 'reward', a.reward,
'duration_seconds', a.duration_seconds, 'budget', a.budget, 'spent', a.spent,
'status', a.status, 'active', a.active, 'total_views', a.total_views,
'advertiser_id', a.advertiser_id, 'advertiser_name', p.username,
'destination_url', a.destination_url,
'daily_view_limit', a.daily_view_limit, 'total_view_limit', a.total_view_limit,
'target_all_countries', a.target_all_countries,
'target_devices', a.target_devices,
'target_countries', COALESCE((SELECT jsonb_agg(c.country_code) FROM ptc_ad_countries c WHERE c.ptc_ad_id = a.id), '[]'::jsonb),
'created_at', a.created_at
) ORDER BY a.created_at DESC), '[]'::jsonb) INTO v_ptc
FROM ptc_ads a
LEFT JOIN profiles p ON p.id = a.advertiser_id
WHERE a.advertiser_id IS NOT NULL
AND (p_status IS NULL OR a.status = p_status);
ELSE
v_ptc := '[]'::jsonb;
END IF;

IF p_type IS NULL OR p_type = 'task' THEN
SELECT COALESCE(jsonb_agg(jsonb_build_object(
'id', t.id, 'title', t.title, 'category', t.category, 'reward', t.reward,
'task_type', t.task_type, 'budget', t.budget, 'spent', t.spent,
'status', t.status, 'active', t.active, 'total_completions', t.total_completions,
'advertiser_id', t.advertiser_id, 'advertiser_name', p.username,
'action_url', t.action_url, 'proof_required', t.proof_required,
'daily_limit', t.daily_limit, 'total_limit', t.total_limit,
'target_all_countries', t.target_all_countries,
'target_countries', COALESCE((SELECT jsonb_agg(c.country_code) FROM task_countries c WHERE c.task_id = t.id), '[]'::jsonb),
'created_at', t.created_at
) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_task
FROM tasks t
LEFT JOIN profiles p ON p.id = t.advertiser_id
WHERE t.advertiser_id IS NOT NULL
AND (p_status IS NULL OR t.status = p_status);
ELSE
v_task := '[]'::jsonb;
END IF;

RETURN jsonb_build_object('ptc_campaigns', v_ptc, 'task_campaigns', v_task);
END;
$function$;

REVOKE EXECUTE ON FUNCTION admin_list_all_campaigns(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_all_campaigns(text, text) TO authenticated;