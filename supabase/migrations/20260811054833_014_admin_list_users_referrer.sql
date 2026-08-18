/*
# Add referrer (upline) username to admin_list_users

1. Modified Functions
- `admin_list_users(p_search, p_limit, p_offset)` — now joins the `referrals` table
  to include `referrer_username` (the username of the user who referred each user,
  or null if the user has no referrer). All existing fields are preserved.
2. Security
- No new tables or columns. Uses the existing `referrals` relationship.
- Function remains SECURITY DEFINER, admin-only (is_admin() check unchanged).
*/

CREATE OR REPLACE FUNCTION admin_list_users(
  p_search text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id, 'username', p.username, 'email', p.email, 'full_name', p.full_name,
    'country', p.country, 'role', p.role, 'status', p.status,
    'available_balance', p.available_balance, 'advertising_balance', p.advertising_balance,
    'total_earned', p.total_earned, 'total_withdrawn', p.total_withdrawn,
    'total_deposited', p.total_deposited, 'ptc_views', p.ptc_views,
    'tasks_completed', p.tasks_completed, 'created_at', p.created_at,
    'ban_reason', p.ban_reason, 'banned_at', p.banned_at, 'banned_by', p.banned_by,
    'referrer_username', ru.username
  ) ORDER BY p.created_at DESC), '[]'::jsonb)
  FROM profiles p
  LEFT JOIN referrals r ON r.referred_id = p.id
  LEFT JOIN profiles ru ON ru.id = r.referrer_id
  WHERE p_search IS NULL OR p_search = ''
     OR p.username ILIKE '%' || p_search || '%'
     OR p.email ILIKE '%' || p_search || '%';
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;
