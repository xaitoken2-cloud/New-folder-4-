/*
# list_my_referrals function
Returns the caller's referrals with username, email, joined date, and reward_amount.
SECURITY DEFINER, search_path = public, REVOKE anon, GRANT authenticated.
*/
CREATE OR REPLACE FUNCTION list_my_referrals()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'username', p.username,
    'email', p.email,
    'created_at', r.created_at,
    'reward_amount', r.reward_amount
  ) ORDER BY r.created_at DESC), '[]'::jsonb)
  FROM referrals r
  JOIN profiles p ON p.id = r.referred_id
  WHERE r.referrer_id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION list_my_referrals() FROM anon;
GRANT EXECUTE ON FUNCTION list_my_referrals() TO authenticated;
