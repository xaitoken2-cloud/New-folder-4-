/*
# Update PTC campaign validation: minimum reward and duration whitelist

## Changes
1. Drop the old overload of `ad_create_ptc_campaign` (without targeting params) to resolve signature ambiguity
2. **ad_create_ptc_campaign** function updated with two validation changes:
   - Minimum reward per view changed from `> 0` to `>= 0.005` (rejects values below $0.005)
   - Duration validation changed from range `1-3600` to whitelist: `10, 15, 20, 30, 60, 90, 120` seconds only
3. No schema changes — only the function body is replaced via CREATE OR REPLACE
4. No RLS or policy changes
5. Grants preserved: REVOKE from anon, GRANT to authenticated

## Important Notes
- The function signature (with targeting params) and all other logic remain identical to migration 039
- Only two validation lines are changed
*/

-- Drop old overload without targeting parameters to resolve ambiguity
DROP FUNCTION IF EXISTS public.ad_create_ptc_campaign(
  text, text, text, text, numeric, integer, text, text, integer, integer, numeric
);

CREATE OR REPLACE FUNCTION public.ad_create_ptc_campaign(
  p_title text, p_description text, p_advertiser text, p_category text,
  p_reward numeric, p_duration_seconds integer, p_destination_url text, p_image_url text,
  p_daily_view_limit integer, p_total_view_limit integer, p_budget numeric,
  p_target_countries text[] DEFAULT NULL,
  p_target_devices text[] DEFAULT ARRAY['desktop','mobile','tablet']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
v_profile profiles%ROWTYPE;
v_ad_id uuid;
v_ref text;
v_tx_id uuid;
v_target_all boolean;
v_devices text[];
v_code text;
BEGIN
SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

IF p_budget IS NULL OR p_budget <= 0 THEN RAISE EXCEPTION 'Invalid budget'; END IF;
IF p_reward IS NULL OR p_reward < 0.005 THEN RAISE EXCEPTION 'Reward per view must be at least 0.005'; END IF;
IF p_duration_seconds IS NULL OR p_duration_seconds NOT IN (10, 15, 20, 30, 60, 90, 120) THEN
RAISE EXCEPTION 'Duration must be one of: 10, 15, 20, 30, 60, 90, 120 seconds'; END IF;
IF p_daily_view_limit IS NULL OR p_daily_view_limit < 1 THEN
RAISE EXCEPTION 'Daily view limit must be at least 1'; END IF;
IF p_total_view_limit IS NULL OR p_total_view_limit < 0 THEN
RAISE EXCEPTION 'Total view limit must be 0 or positive'; END IF;
IF p_budget > v_profile.advertising_balance THEN
RAISE EXCEPTION 'Insufficient advertising balance (need %, have %)', p_budget, v_profile.advertising_balance; END IF;

v_devices := COALESCE(p_target_devices, ARRAY['desktop','mobile','tablet']);
IF array_length(v_devices, 1) IS NULL OR array_length(v_devices, 1) <= 0 THEN
RAISE EXCEPTION 'At least one device type must be selected'; END IF;
IF NOT (v_devices <@ ARRAY['desktop','mobile','tablet']::text[]) THEN
RAISE EXCEPTION 'Invalid device type in target_devices'; END IF;

v_target_all := (p_target_countries IS NULL OR array_length(p_target_countries, 1) IS NULL);

-- Deduct budget from advertising balance
UPDATE profiles SET advertising_balance = advertising_balance - p_budget WHERE id = auth.uid();

-- Create campaign (status='pending' for admin approval)
INSERT INTO ptc_ads (
title, description, advertiser, category, reward, duration_seconds,
destination_url, image_url, daily_view_limit, total_view_limit,
active, advertiser_id, budget, spent, status,
target_all_countries, target_devices
) VALUES (
p_title, COALESCE(p_description, ''), COALESCE(p_advertiser, ''), COALESCE(p_category, 'general'),
p_reward, p_duration_seconds, COALESCE(p_destination_url, ''), COALESCE(p_image_url, ''),
p_daily_view_limit, p_total_view_limit, false, auth.uid(), p_budget, 0, 'pending',
v_target_all, v_devices
) RETURNING id INTO v_ad_id;

IF NOT v_target_all THEN
FOREACH v_code IN ARRAY p_target_countries LOOP
v_code := upper(btrim(v_code));
IF v_code <> '' THEN
INSERT INTO ptc_ad_countries (ptc_ad_id, country_code) VALUES (v_ad_id, v_code)
ON CONFLICT (ptc_ad_id, country_code) DO NOTHING;
END IF;
END LOOP;
END IF;

v_ref := 'ad_spend:ptc:' || v_ad_id::text;
INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
VALUES (auth.uid(), 'ad_spend', -p_budget, 'ptc_ad', v_ad_id, v_ref,
'PTC campaign budget allocation', 'completed')
ON CONFLICT (reference) DO NOTHING
RETURNING id INTO v_tx_id;

RETURN jsonb_build_object('ok', true, 'campaign_id', v_ad_id, 'status', 'pending');
END;
$function$;

REVOKE EXECUTE ON FUNCTION ad_create_ptc_campaign(
  text, text, text, text, numeric, integer, text, text, integer, integer, numeric, text[], text[]
) FROM anon;
GRANT EXECUTE ON FUNCTION ad_create_ptc_campaign(
  text, text, text, text, numeric, integer, text, text, integer, integer, numeric, text[], text[]
) TO authenticated;