/*
# Server-Side Task Country-Eligibility Filtering

1. Purpose
   listTasks() and getTask() currently use raw SELECT on the tasks table,
   which leaks country-restricted tasks to ineligible users (RLS allows all
   authenticated users to SELECT from tasks). These RPCs filter server-side
   using the exact same eligibility check already in task_submit.

2. Security
   - Both functions are SECURITY DEFINER, revoked from anon, granted to authenticated.
   - Reuse the same country check from task_submit (migration 041):
     IF NOT target_all_countries AND (country IS NULL/'' OR not in task_countries) → exclude.

3. Scope
   - Only affects the user-facing task listing and detail views.
   - Does NOT change tasks RLS, task_submit, PTC ads, or advertiser/admin campaign RPCs.
*/

-- list_available_tasks: returns active tasks eligible for the calling user's country
CREATE OR REPLACE FUNCTION public.list_available_tasks()
RETURNS SETOF tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_country text;
BEGIN
  SELECT country INTO v_country FROM profiles WHERE id = auth.uid();

  RETURN QUERY
  SELECT t.*
  FROM tasks t
  WHERE t.active = true
    AND (
      t.target_all_countries = true
      OR (
        v_country IS NOT NULL
        AND v_country <> ''
        AND EXISTS (
          SELECT 1 FROM task_countries tc
          WHERE tc.task_id = t.id AND upper(tc.country_code) = upper(v_country)
        )
      )
    )
  ORDER BY t.created_at DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION list_available_tasks() FROM anon;
GRANT EXECUTE ON FUNCTION list_available_tasks() TO authenticated;

-- get_available_task: returns a single task only if eligible for the calling user's country
CREATE OR REPLACE FUNCTION public.get_available_task(p_task_id uuid)
RETURNS tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_country text;
  v_task tasks%ROWTYPE;
BEGIN
  SELECT country INTO v_country FROM profiles WHERE id = auth.uid();

  SELECT t.* INTO v_task
  FROM tasks t
  WHERE t.id = p_task_id
    AND t.active = true
    AND (
      t.target_all_countries = true
      OR (
        v_country IS NOT NULL
        AND v_country <> ''
        AND EXISTS (
          SELECT 1 FROM task_countries tc
          WHERE tc.task_id = t.id AND upper(tc.country_code) = upper(v_country)
        )
      )
    );

  RETURN v_task;
END;
$function$;

REVOKE EXECUTE ON FUNCTION get_available_task(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION get_available_task(uuid) TO authenticated;