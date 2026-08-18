-- Fix ad_get_dashboard(): the third SELECT INTO overwrote PTC budget/spent
-- with task-only values, so dashboard totals ignored PTC campaigns entirely.
-- Now sums budget/spent across both ptc_ads and tasks for the advertiser.

CREATE OR REPLACE FUNCTION ad_get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_ptc_total integer;
  v_ptc_active integer;
  v_task_total integer;
  v_task_active integer;
  v_ptc_budget numeric(18,8);
  v_ptc_spent numeric(18,8);
  v_task_budget numeric(18,8);
  v_task_spent numeric(18,8);
  v_total_budget numeric(18,8);
  v_total_spent numeric(18,8);
  v_ptc_views integer;
  v_task_completions integer;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT count(*), count(*) FILTER (WHERE status = 'active'),
    COALESCE(sum(budget), 0), COALESCE(sum(spent), 0), COALESCE(sum(total_views), 0)
    INTO v_ptc_total, v_ptc_active, v_ptc_budget, v_ptc_spent, v_ptc_views
    FROM ptc_ads WHERE advertiser_id = auth.uid();

  SELECT count(*), count(*) FILTER (WHERE status = 'active'),
    COALESCE(sum(budget), 0), COALESCE(sum(spent), 0), COALESCE(sum(total_completions), 0)
    INTO v_task_total, v_task_active, v_task_budget, v_task_spent, v_task_completions
    FROM tasks WHERE advertiser_id = auth.uid();

  v_total_budget := COALESCE(v_ptc_budget, 0) + COALESCE(v_task_budget, 0);
  v_total_spent := COALESCE(v_ptc_spent, 0) + COALESCE(v_task_spent, 0);

  RETURN jsonb_build_object(
    'advertising_balance', v_profile.advertising_balance,
    'ptc_campaigns', v_ptc_total,
    'ptc_active', v_ptc_active,
    'task_campaigns', v_task_total,
    'task_active', v_task_active,
    'total_budget', v_total_budget,
    'total_spent', v_total_spent,
    'ptc_views', v_ptc_views,
    'task_completions', v_task_completions
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_get_dashboard() FROM anon;
GRANT EXECUTE ON FUNCTION ad_get_dashboard() TO authenticated;
