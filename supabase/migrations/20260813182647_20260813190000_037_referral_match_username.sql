/*
# Match referral code against username instead of referral_code
1. Change
- handle_new_user() previously matched the incoming referral_code metadata
  against profiles.referral_code. Referral links now use the username,
  so the trigger must match against profiles.username instead.
2. Details
- Only the WHERE clause in the referral lookup SELECT is changed:
  lower(referral_code) -> lower(username).
- All other logic (self-referral prevention, referral row insert, profile
  insert, referral code generation) is unchanged.
*/
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
COALESCE(v_meta->>'country', ''),
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