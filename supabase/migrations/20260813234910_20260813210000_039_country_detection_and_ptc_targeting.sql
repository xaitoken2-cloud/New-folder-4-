-- Country detection lockdown + PTC campaign targeting (country + device)

-- 1. Lock down profiles.country: revoke user writes, add country_detected
REVOKE UPDATE (country) ON profiles FROM authenticated;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS country_detected boolean NOT NULL DEFAULT false;

-- 2. handle_new_user: stop trusting raw_user_meta_data->>'country'
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
v_referral_code text;
v_referred_by uuid;
v_meta jsonb;
BEGIN
v_referral_code := generate_referral_code();
v_meta := COALESCE(new.raw_user_meta_data, '{}'::jsonb);

-- Resolve referral code from metadata (case-insensitive)
IF v_meta ? 'referral_code' THEN
SELECT id INTO v_referred_by FROM profiles
WHERE lower(username) = lower(v_meta->>'referral_code')
LIMIT 1;
IF v_referred_by = new.id THEN
v_referred_by := NULL; -- prevent self-referral
END IF;
END IF;

INSERT INTO profiles (
id, username, full_name, email, country, referral_code, referred_by
) VALUES (
new.id,
COALESCE(v_meta->>'username', split_part(new.email, '@', 1)),
COALESCE(v_meta->>'full_name', v_meta->>'username', split_part(new.email, '@', 1)),
COALESCE(new.email, ''),
'',
v_referral_code,
v_referred_by
);

IF v_referred_by IS NOT NULL THEN
INSERT INTO referrals (referrer_id, referred_id)
VALUES (v_referred_by, new.id)
ON CONFLICT (referred_id) DO NOTHING;
END IF;

RETURN new;
END;
$function$;

-- 6. Admin-only override function
CREATE OR REPLACE FUNCTION public.admin_update_user_country(p_user_id uuid, p_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE profiles SET country = COALESCE(p_country, ''), country_detected = true
    WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'admin_update_user_country', 'profile', p_user_id::text,
      jsonb_build_object('country', p_country));
  RETURN jsonb_build_object('ok', true);
END; $$;

REVOKE EXECUTE ON FUNCTION admin_update_user_country(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_user_country(uuid, text) TO authenticated;

-- 8. PTC campaign targeting schema
ALTER TABLE ptc_ads ADD COLUMN IF NOT EXISTS target_all_countries boolean NOT NULL DEFAULT true;
ALTER TABLE ptc_ads ADD COLUMN IF NOT EXISTS target_devices text[] NOT NULL DEFAULT ARRAY['desktop','mobile','tablet'];

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ptc_ads_target_devices_valid'
  ) THEN
    ALTER TABLE ptc_ads ADD CONSTRAINT ptc_ads_target_devices_valid
      CHECK (target_devices <@ ARRAY['desktop','mobile','tablet']::text[] AND array_length(target_devices,1) > 0);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS ptc_ad_countries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ptc_ad_id uuid NOT NULL REFERENCES ptc_ads(id) ON DELETE CASCADE,
  country_code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ptc_ad_id, country_code)
);
CREATE INDEX IF NOT EXISTS ptc_ad_countries_ad_id_idx ON ptc_ad_countries (ptc_ad_id);
ALTER TABLE ptc_ad_countries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'ptc_ad_countries' AND policyname = 'ptc_ad_countries_select_authenticated'
  ) THEN
    CREATE POLICY "ptc_ad_countries_select_authenticated" ON ptc_ad_countries FOR SELECT
      TO authenticated USING (true);
  END IF;
END $$;

-- 9. ad_create_ptc_campaign with targeting params
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
IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Invalid reward per view'; END IF;
IF p_duration_seconds IS NULL OR p_duration_seconds < 1 OR p_duration_seconds > 3600 THEN
RAISE EXCEPTION 'Duration must be between 1 and 3600 seconds'; END IF;
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

-- 10. ad_list_campaigns with targeting fields
CREATE OR REPLACE FUNCTION public.ad_list_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
'id', id, 'title', title, 'category', category, 'reward', reward,
'task_type', task_type, 'budget', budget, 'spent', spent,
'status', status, 'active', active, 'total_completions', total_completions,
'daily_limit', daily_limit, 'total_limit', total_limit,
'created_at', created_at
) ORDER BY created_at DESC)
FROM tasks WHERE advertiser_id = auth.uid()
)
);
END;
$function$;

-- 11. admin_list_all_campaigns with targeting fields (PTC only)
CREATE OR REPLACE FUNCTION public.admin_list_all_campaigns(p_type text, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

-- 11b. admin_list_pending_campaigns with targeting fields (PTC only)
CREATE OR REPLACE FUNCTION public.admin_list_pending_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
'created_at', t.created_at
) ORDER BY t.created_at DESC)
FROM tasks t
LEFT JOIN profiles p ON p.id = t.advertiser_id
WHERE t.status = 'pending' AND t.advertiser_id IS NOT NULL
)
);
END;
$function$;

-- 12. ptc_start with country + device targeting enforcement
CREATE OR REPLACE FUNCTION public.ptc_start(p_ad_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
v_ad ptc_ads%ROWTYPE;
v_profile profiles%ROWTYPE;
v_view ptc_ad_views%ROWTYPE;
v_today_count integer;
v_existing ptc_ad_views%ROWTYPE;
v_ua text;
v_device text;
BEGIN
SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

-- Expire stale pending sessions (past expires_at) for this user
UPDATE ptc_ad_views SET status = 'expired'
WHERE user_id = auth.uid() AND status = 'pending'
AND expires_at IS NOT NULL AND now() > expires_at;

-- Cancel any existing pending view session for this user (any ad).
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

-- Country targeting check
IF NOT v_ad.target_all_countries THEN
  IF v_profile.country IS NULL OR v_profile.country = '' THEN
    RAISE EXCEPTION 'This advertisement is not available in your region';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ptc_ad_countries
    WHERE ptc_ad_id = v_ad.id AND upper(country_code) = upper(v_profile.country)
  ) THEN
    RAISE EXCEPTION 'This advertisement is not available in your region';
  END IF;
END IF;

-- Device targeting check: derive device type from the User-Agent header
-- exposed by PostgREST via the request.headers GUC.
v_ua := lower(COALESCE(
  (current_setting('request.headers', true)::jsonb ->> 'user-agent'), ''
));
IF v_ua = '' THEN
  v_device := 'desktop';
ELSIF v_ua ~ 'ipad|tablet|(android(?!.*mobile))' THEN
  v_device := 'tablet';
ELSIF v_ua ~ 'mobile|iphone|android' THEN
  v_device := 'mobile';
ELSE
  v_device := 'desktop';
END IF;

IF NOT (v_device = ANY(v_ad.target_devices)) THEN
  RAISE EXCEPTION 'This advertisement is not available on your device type';
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
$function$;