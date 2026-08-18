-- Fix admin_stats(): migration 025 referenced non-existent column owner_id.
-- Merge 012's working campaign/advertiser logic with 025's XC stats.

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
  v_total_deposited numeric(18,8);
  v_total_withdrawn numeric(18,8);
  v_total_paid_out numeric(18,8);
  v_total_balance numeric(18,8);
  v_total_ad_balance numeric(18,8);
  v_ptc_campaigns integer;
  v_task_campaigns integer;
  v_pending_campaigns integer;
  v_active_campaigns integer;
  v_completed_campaigns integer;
  v_total_ad_spend numeric(18,8);
  v_active_advertisers integer;
  v_ptc_pending integer;
  v_task_pending integer;
  v_ptc_active integer;
  v_task_active integer;
  v_ptc_completed integer;
  v_task_completed integer;
  v_ptc_spent numeric(18,8);
  v_task_spent numeric(18,8);
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
  SELECT count(*) INTO v_active_ads FROM ptc_ads WHERE active;
  SELECT count(*) INTO v_active_tasks FROM tasks WHERE active;
  SELECT COALESCE(sum(total_views),0) INTO v_total_ptc_views FROM ptc_ads;
  SELECT count(*) INTO v_total_task_completions FROM task_completions WHERE status = 'approved';
  SELECT count(*) INTO v_pending_deposits FROM deposits WHERE status = 'pending';
  SELECT count(*) INTO v_pending_withdrawals FROM withdrawals WHERE status = 'pending';
  SELECT COALESCE(sum(total_deposited),0) INTO v_total_deposited FROM profiles;
  SELECT COALESCE(sum(total_withdrawn),0) INTO v_total_withdrawn FROM profiles;
  SELECT COALESCE(sum(total_earned),0) INTO v_total_paid_out FROM profiles;
  SELECT COALESCE(sum(available_balance),0) INTO v_total_balance FROM profiles;
  SELECT COALESCE(sum(advertising_balance),0) INTO v_total_ad_balance FROM profiles;

  SELECT count(*) INTO v_ptc_campaigns FROM ptc_ads WHERE advertiser_id IS NOT NULL;
  SELECT count(*) INTO v_task_campaigns FROM tasks WHERE advertiser_id IS NOT NULL;

  SELECT count(*) INTO v_ptc_pending FROM ptc_ads WHERE status = 'pending' AND advertiser_id IS NOT NULL;
  SELECT count(*) INTO v_task_pending FROM tasks WHERE status = 'pending' AND advertiser_id IS NOT NULL;
  v_pending_campaigns := v_ptc_pending + v_task_pending;

  SELECT count(*) INTO v_ptc_active FROM ptc_ads WHERE status = 'active' AND advertiser_id IS NOT NULL;
  SELECT count(*) INTO v_task_active FROM tasks WHERE status = 'active' AND advertiser_id IS NOT NULL;
  v_active_campaigns := v_ptc_active + v_task_active;

  SELECT count(*) INTO v_ptc_completed FROM ptc_ads WHERE status = 'completed' AND advertiser_id IS NOT NULL;
  SELECT count(*) INTO v_task_completed FROM tasks WHERE status = 'completed' AND advertiser_id IS NOT NULL;
  v_completed_campaigns := v_ptc_completed + v_task_completed;

  SELECT COALESCE(sum(spent),0) INTO v_ptc_spent FROM ptc_ads WHERE advertiser_id IS NOT NULL;
  SELECT COALESCE(sum(spent),0) INTO v_task_spent FROM tasks WHERE advertiser_id IS NOT NULL;
  v_total_ad_spend := v_ptc_spent + v_task_spent;

  SELECT count(DISTINCT aid) INTO v_active_advertisers FROM (
    SELECT advertiser_id AS aid FROM ptc_ads WHERE advertiser_id IS NOT NULL AND status = 'active'
    UNION
    SELECT advertiser_id AS aid FROM tasks WHERE advertiser_id IS NOT NULL AND status = 'active'
  ) sub;

  -- XC statistics
  SELECT COALESCE(sum(amount),0) INTO v_xc_total_issued
    FROM transactions WHERE currency = 'XC' AND amount > 0 AND status = 'completed';
  SELECT COALESCE(sum(amount),0) INTO v_xc_ptc_earned
    FROM transactions WHERE currency = 'XC' AND type = 'ptc_reward' AND amount > 0 AND status = 'completed';
  SELECT COALESCE(sum(amount),0) INTO v_xc_offer_earned
    FROM transactions WHERE currency = 'XC' AND type = 'offer_reward' AND amount > 0 AND status = 'completed';
  SELECT COALESCE(sum(amount),0) INTO v_xc_task_earned
    FROM transactions WHERE currency = 'XC' AND type = 'task_reward' AND amount > 0 AND status = 'completed';
  SELECT COALESCE(sum(xc_balance),0) INTO v_xc_total_balance FROM profiles;

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
    'ptc_campaigns', v_ptc_campaigns,
    'task_campaigns', v_task_campaigns,
    'pending_campaigns', v_pending_campaigns,
    'active_campaigns', v_active_campaigns,
    'completed_campaigns', v_completed_campaigns,
    'total_ad_spend', v_total_ad_spend,
    'active_advertisers', v_active_advertisers,
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
