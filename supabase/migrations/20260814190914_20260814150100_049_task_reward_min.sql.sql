/*
# Update task campaign validation: minimum reward per task

## Changes
1. **ad_create_task_campaign** function updated with one validation change:
   - Minimum reward per task changed from `> 0` to `>= 0.01` (rejects values below $0.01)
2. No schema changes — only the function body is replaced via CREATE OR REPLACE
3. No RLS or policy changes
4. Grants preserved: REVOKE from anon, GRANT to authenticated

## Important Notes
- The function signature and all other logic remain identical to migration 047
- Only one validation line is changed
*/

CREATE OR REPLACE FUNCTION public.ad_create_task_campaign(
  p_title text, p_description text, p_instructions text, p_category text,
  p_task_type text, p_reward numeric, p_action_url text,
  p_proof_required boolean, p_proof_instructions text,
  p_daily_limit integer, p_total_limit integer, p_budget numeric,
  p_target_countries text[] DEFAULT NULL,
  p_proof_image_url text DEFAULT NULL
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
  IF p_reward IS NULL OR p_reward < 0.01 THEN RAISE EXCEPTION 'Reward per task must be at least 0.01'; END IF;
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
    target_all_countries, proof_image_url
  ) VALUES (
    p_title, COALESCE(p_description, ''), COALESCE(p_instructions, ''),
    COALESCE(p_category, 'general'), COALESCE(p_task_type, 'custom'),
    p_reward, COALESCE(p_action_url, ''), COALESCE(p_proof_required, false),
    COALESCE(p_proof_instructions, ''), p_daily_limit, p_total_limit,
    false, auth.uid(), p_budget, 0, 'pending',
    v_target_all, p_proof_image_url
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