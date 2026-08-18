/*
# Admin Diagnostic: Task Country Targeting Inspector

1. Purpose
   Read-only diagnostic RPC for admins to inspect why task_submit rejects a user
   with "This task is not available in your region". Returns the task's
   target_all_countries flag, its task_countries rows, and the specified user's
   profile country fields, plus a human-readable diagnosis string.

2. Security
   - SECURITY DEFINER, admin-only (is_admin() check).
   - Read-only: no writes to any table.
   - REVOKE from anon, GRANT to authenticated.
*/

CREATE OR REPLACE FUNCTION public.admin_debug_task_targeting(p_task_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_task tasks%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_countries text[];
  v_diagnosis text;
  v_uid uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  v_uid := COALESCE(p_user_id, auth.uid());

  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Task not found', 'task_id', p_task_id);
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;

  SELECT COALESCE(array_agg(country_code), ARRAY[]::text[]) INTO v_countries
  FROM task_countries WHERE task_id = p_task_id;

  IF v_task.target_all_countries THEN
    v_diagnosis := 'Task is worldwide (target_all_countries=true). No country restriction.';
  ELSIF v_profile.country IS NULL OR v_profile.country = '' THEN
    v_diagnosis := 'Task is country-restricted but user profile.country is empty. User cannot be matched.';
  ELSIF EXISTS (
    SELECT 1 FROM task_countries
    WHERE task_id = v_task.id AND upper(country_code) = upper(v_profile.country)
  ) THEN
    v_diagnosis := 'Country match found. Should NOT be rejected.';
  ELSE
    v_diagnosis := 'Genuine country mismatch. User country=' || v_profile.country || ' is not in target list.';
  END IF;

  RETURN jsonb_build_object(
    'task_id', v_task.id,
    'task_title', v_task.title,
    'target_all_countries', v_task.target_all_countries,
    'target_countries', v_countries,
    'user_id', v_uid,
    'user_country', v_profile.country,
    'user_country_detected', v_profile.country_detected,
    'diagnosis', v_diagnosis
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION admin_debug_task_targeting(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_debug_task_targeting(uuid, uuid) TO authenticated;