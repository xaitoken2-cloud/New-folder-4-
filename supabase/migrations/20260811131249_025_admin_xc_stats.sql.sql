-- Extend admin_stats to include XC statistics and USD/XC separation

CREATE OR REPLACE FUNCTION admin_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_users integer;
  v_active_ads integer;
  v_active_tasks integer;
  v_total_ptc_views integer;
  v_total_task_completions integer;
  v_pending_deposits integer;
  v_pending_withdrawals integer;
  v_total_deposited numeric;
  v_total_withdrawn numeric;
  v_total_paid_out numeric;
  v_total_balance numeric;
  v_total_ad_balance numeric;
  v_pending_campaigns integer;
  v_active_advertisers integer;
  v_total_ad_spend numeric;
  v_ptc_campaigns integer;
  v_task_campaigns integer;
  v_active_campaigns integer;
  v_completed_campaigns integer;
  -- XC stats
  v_xc_total_issued numeric;
  v_xc_ptc_earned numeric;
  v_xc_offer_earned numeric;
  v_xc_task_earned numeric;
  v_xc_total_balance numeric;
  v_reward_multiplier numeric;
  v_xc_value_usd numeric;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT count(*) INTO v_users FROM profiles;
  SELECT count(*) INTO v_active_ads FROM ptc_ads WHERE active = true;
  SELECT count(*) INTO v_active_tasks FROM tasks WHERE active = true;
  SELECT coalesce(sum(ptc_views), 0) INTO v_total_ptc_views FROM profiles;
  SELECT coalesce(sum(tasks_completed), 0) INTO v_total_task_completions FROM profiles;
  SELECT count(*) INTO v_pending_deposits FROM deposits WHERE status = 'pending';
  SELECT count(*) INTO v_pending_withdrawals FROM withdrawals WHERE status = 'pending';
  SELECT coalesce(sum(amount), 0) INTO v_total_deposited FROM deposits WHERE status = 'approved';
  SELECT coalesce(sum(amount), 0) INTO v_total_withdrawn FROM withdrawals WHERE status = 'paid';
  SELECT coalesce(sum(amount), 0) INTO v_total_paid_out FROM transactions WHERE type = 'withdrawal' AND status = 'completed';
  SELECT coalesce(sum(available_balance), 0) INTO v_total_balance FROM profiles;
  SELECT coalesce(sum(advertising_balance), 0) INTO v_total_ad_balance FROM profiles;
  SELECT count(*) INTO v_pending_campaigns FROM ptc_ads WHERE status = 'pending' OR active = false;
  SELECT count(DISTINCT owner_id) INTO v_active_advertisers FROM ptc_ads WHERE active = true;
  SELECT coalesce(sum(amount), 0) INTO v_total_ad_spend FROM transactions WHERE type = 'ad_spend';
  SELECT count(*) INTO v_ptc_campaigns FROM ptc_ads;
  SELECT count(*) INTO v_task_campaigns FROM tasks;
  SELECT count(*) INTO v_active_campaigns FROM ptc_ads WHERE active = true;
  SELECT count(*) INTO v_completed_campaigns FROM ptc_ads WHERE total_view_limit > 0 AND total_views >= total_view_limit;

  -- XC statistics
  SELECT coalesce(sum(amount), 0) INTO v_xc_total_issued
    FROM transactions WHERE currency = 'XC' AND amount > 0 AND status = 'completed';
  SELECT coalesce(sum(amount), 0) INTO v_xc_ptc_earned
    FROM transactions WHERE currency = 'XC' AND type = 'ptc_reward' AND amount > 0 AND status = 'completed';
  SELECT coalesce(sum(amount), 0) INTO v_xc_offer_earned
    FROM transactions WHERE currency = 'XC' AND type = 'offer_reward' AND amount > 0 AND status = 'completed';
  SELECT coalesce(sum(amount), 0) INTO v_xc_task_earned
    FROM transactions WHERE currency = 'XC' AND type = 'task_reward' AND amount > 0 AND status = 'completed';
  SELECT coalesce(sum(xc_balance), 0) INTO v_xc_total_balance FROM profiles;

  SELECT reward_multiplier, xc_value_usd INTO v_reward_multiplier, v_xc_value_usd
    FROM app_settings WHERE id = 1;

  RETURN jsonb_build_object(
    'users', v_users,
    'active_ads', v_active_ads,
    'active_tasks', v_active_tasks,
    'total_ptc_views', v_total_ptc_views,
    'total_task_completions', v_total_task_completions,
    'pending_deposits', v_pending_deposits,
    'pending_withdrawals', v_pending_withdrawals,
    'total_deposited', v_total_deposited,
    'total_withdrawn', v_total_withdrawn,
    'total_paid_out', v_total_paid_out,
    'total_balance', v_total_balance,
    'total_ad_balance', v_total_ad_balance,
    'pending_campaigns', v_pending_campaigns,
    'active_advertisers', v_active_advertisers,
    'total_ad_spend', v_total_ad_spend,
    'ptc_campaigns', v_ptc_campaigns,
    'task_campaigns', v_task_campaigns,
    'active_campaigns', v_active_campaigns,
    'completed_campaigns', v_completed_campaigns,
    'xc_total_issued', v_xc_total_issued,
    'xc_ptc_earned', v_xc_ptc_earned,
    'xc_offer_earned', v_xc_offer_earned,
    'xc_task_earned', v_xc_task_earned,
    'xc_total_balance', v_xc_total_balance,
    'reward_multiplier', v_reward_multiplier,
    'xc_value_usd', v_xc_value_usd
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_stats() FROM anon;
GRANT EXECUTE ON FUNCTION admin_stats() TO authenticated;
