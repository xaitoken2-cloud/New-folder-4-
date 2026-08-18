/*
# Admin: Undetected Country Backfill Tools

1. Purpose
   Admin-only RPCs to identify and bulk-set country for users whose
   profiles.country was never detected (country = '' AND country_detected = false).
   These users get incorrectly rejected from country-restricted tasks.

2. Security
   - Both functions are SECURITY DEFINER, admin-only (is_admin() check).
   - admin_list_undetected_users is read-only.
   - admin_bulk_set_country writes to profiles + audit_logs, matching
     the existing admin_update_user_country pattern exactly.
   - REVOKE from anon, GRANT to authenticated.

3. Scope
   Only touches profiles.country for rows WHERE country = '' AND country_detected = false.
   Does NOT touch tasks, ptc_ads, task_countries, or ptc_ad_countries.
*/

-- Returns profiles with undetected country (empty + not manually set)
CREATE OR REPLACE FUNCTION public.admin_list_undetected_users()
RETURNS TABLE (
  id uuid,
  username text,
  email text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN QUERY
  SELECT p.id, p.username, au.email, p.created_at
  FROM profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  WHERE (p.country IS NULL OR p.country = '')
    AND p.country_detected = false
  ORDER BY p.created_at DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION admin_list_undetected_users() FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_undetected_users() TO authenticated;

-- Bulk-set country for a list of users (only those currently undetected)
CREATE OR REPLACE FUNCTION public.admin_bulk_set_country(p_user_ids uuid[], p_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
  v_uid uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  v_count := 0;
  FOREACH v_uid IN ARRAY p_user_ids LOOP
    UPDATE profiles
    SET country = COALESCE(p_country, ''), country_detected = true
    WHERE id = v_uid
      AND (country IS NULL OR country = '')
      AND country_detected = false;

    IF FOUND THEN
      v_count := v_count + 1;
      INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'admin_bulk_set_country', 'profile', v_uid::text,
        jsonb_build_object('country', p_country));
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'updated_count', v_count);
END;
$function$;

REVOKE EXECUTE ON FUNCTION admin_bulk_set_country(uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_bulk_set_country(uuid[], text) TO authenticated;