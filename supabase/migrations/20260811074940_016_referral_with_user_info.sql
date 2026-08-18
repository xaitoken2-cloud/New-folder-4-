/*
# Referral list with referred user info

1. New Functions
- `get_my_referrals()` — returns the caller's referrals joined with the referred
  user's username and email. SECURITY DEFINER because the profiles table RLS
  only allows reading your own row, so a direct join would return null for
  other users' info.
2. Security
- SECURITY DEFINER, search_path = public.
- REVOKE EXECUTE FROM anon; GRANT EXECUTE TO authenticated.
- Only returns rows where the caller is the referrer.
*/

CREATE OR REPLACE FUNCTION get_my_referrals()
RETURNS TABLE (
  id uuid,
  referrer_id uuid,
  referred_id uuid,
  qualified boolean,
  reward_amount numeric,
  created_at timestamptz,
  qualified_at timestamptz,
  referred_username text,
  referred_email text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.referrer_id,
    r.referred_id,
    r.qualified,
    r.reward_amount,
    r.created_at,
    r.qualified_at,
    p.username AS referred_username,
    p.email AS referred_email
  FROM referrals r
  JOIN profiles p ON p.id = r.referred_id
  WHERE r.referrer_id = auth.uid()
  ORDER BY r.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION get_my_referrals() FROM anon;
GRANT EXECUTE ON FUNCTION get_my_referrals() TO authenticated;
