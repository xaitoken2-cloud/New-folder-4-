-- Drop functions whose signatures changed
DROP FUNCTION IF EXISTS admin_list_users(text, integer, integer);
DROP FUNCTION IF EXISTS admin_list_transactions(integer, integer);

-- ========== Enhanced admin_stats ==========
CREATE OR REPLACE FUNCTION admin_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
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
    'active_advertisers', v_active_advertisers
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_stats() FROM anon;
GRANT EXECUTE ON FUNCTION admin_stats() TO authenticated;

-- ========== admin_set_user_role ==========
CREATE OR REPLACE FUNCTION admin_set_user_role(p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_old_role text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_role NOT IN ('user','moderator','admin') THEN RAISE EXCEPTION 'Invalid role'; END IF;

  SELECT role INTO v_old_role FROM profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  UPDATE profiles SET role = p_role WHERE id = p_user_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'set_user_role', 'user', p_user_id::text,
      jsonb_build_object('old_role', v_old_role, 'new_role', p_role));

  RETURN jsonb_build_object('ok', true, 'old_role', v_old_role, 'new_role', p_role);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_set_user_role(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_set_user_role(uuid, text) TO authenticated;

-- ========== admin_adjust_balance ==========
CREATE OR REPLACE FUNCTION admin_adjust_balance(
  p_user_id uuid,
  p_balance_type text,
  p_amount numeric,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_before numeric(18,8);
  v_after numeric(18,8);
  v_tx_id uuid;
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN RAISE EXCEPTION 'Amount must be non-zero'; END IF;
  IF p_balance_type NOT IN ('available','advertising') THEN RAISE EXCEPTION 'Invalid balance type'; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  IF p_balance_type = 'available' THEN
    v_before := v_profile.available_balance;
    v_after := v_before + p_amount;
    IF v_after < 0 THEN RAISE EXCEPTION 'Resulting balance cannot be negative (before: %, adjustment: %)', v_before, p_amount; END IF;
    UPDATE profiles SET available_balance = v_after WHERE id = p_user_id;
  ELSE
    v_before := v_profile.advertising_balance;
    v_after := v_before + p_amount;
    IF v_after < 0 THEN RAISE EXCEPTION 'Resulting advertising balance cannot be negative (before: %, adjustment: %)', v_before, p_amount; END IF;
    UPDATE profiles SET advertising_balance = v_after WHERE id = p_user_id;
  END IF;

  v_ref := 'admin_adjust:' || p_user_id::text || ':' || extract(epoch from now())::int::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (p_user_id, 'adjustment', p_amount, 'admin_adjustment', auth.uid(), v_ref,
      COALESCE(p_reason, 'Admin balance adjustment'), 'completed')
    RETURNING id INTO v_tx_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'adjust_balance', 'user', p_user_id::text,
      jsonb_build_object('balance_type', p_balance_type, 'amount', p_amount,
        'before', v_before, 'after', v_after, 'reason', p_reason,
        'transaction_id', v_tx_id));

  RETURN jsonb_build_object('ok', true, 'before', v_before, 'after', v_after, 'transaction_id', v_tx_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_adjust_balance(uuid, text, numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_adjust_balance(uuid, text, numeric, text) TO authenticated;

-- ========== admin_list_advertisers ==========
CREATE OR REPLACE FUNCTION admin_list_advertisers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'email', p.email,
    'advertising_balance', p.advertising_balance,
    'status', p.status,
    'created_at', p.created_at,
    'ptc_campaigns', COALESCE(ptc.cnt, 0),
    'task_campaigns', COALESCE(tc.cnt, 0),
    'total_spent', COALESCE(ptc.spent, 0) + COALESCE(tc.spent, 0),
    'active_campaigns', COALESCE(ptc.active, 0) + COALESCE(tc.active, 0),
    'pending_campaigns', COALESCE(ptc.pending, 0) + COALESCE(tc.pending, 0)
  ) ORDER BY p.created_at DESC), '[]'::jsonb)
  FROM profiles p
  LEFT JOIN (
    SELECT advertiser_id,
      count(*) AS cnt,
      COALESCE(sum(spent),0) AS spent,
      count(*) FILTER (WHERE status = 'active') AS active,
      count(*) FILTER (WHERE status = 'pending') AS pending
    FROM ptc_ads WHERE advertiser_id IS NOT NULL
    GROUP BY advertiser_id
  ) ptc ON ptc.advertiser_id = p.id
  LEFT JOIN (
    SELECT advertiser_id,
      count(*) AS cnt,
      COALESCE(sum(spent),0) AS spent,
      count(*) FILTER (WHERE status = 'active') AS active,
      count(*) FILTER (WHERE status = 'pending') AS pending
    FROM tasks WHERE advertiser_id IS NOT NULL
    GROUP BY advertiser_id
  ) tc ON tc.advertiser_id = p.id
  WHERE p.advertising_balance > 0
     OR ptc.advertiser_id IS NOT NULL
     OR tc.advertiser_id IS NOT NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_advertisers() FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_advertisers() TO authenticated;

-- ========== admin_list_all_campaigns ==========
CREATE OR REPLACE FUNCTION admin_list_all_campaigns(p_type text, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ptc jsonb;
  v_task jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type IS NULL OR p_type = 'ptc' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'title', a.title, 'category', a.category, 'reward', a.reward,
      'duration_seconds', a.duration_seconds, 'budget', a.budget, 'spent', a.spent,
      'status', a.status, 'active', a.active, 'total_views', a.total_views,
      'advertiser_id', a.advertiser_id, 'advertiser_name', p.username,
      'destination_url', a.destination_url,
      'daily_view_limit', a.daily_view_limit, 'total_view_limit', a.total_view_limit,
      'created_at', a.created_at
    ) ORDER BY a.created_at DESC), '[]'::jsonb) INTO v_ptc
    FROM ptc_ads a
    LEFT JOIN profiles p ON p.id = a.advertiser_id
    WHERE a.advertiser_id IS NOT NULL
      AND (p_status IS NULL OR a.status = p_status);
  ELSE
    v_ptc := '[]'::jsonb;
  END IF;

  IF p_type IS NULL OR p_type = 'task' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', t.id, 'title', t.title, 'category', t.category, 'reward', t.reward,
      'task_type', t.task_type, 'budget', t.budget, 'spent', t.spent,
      'status', t.status, 'active', t.active, 'total_completions', t.total_completions,
      'advertiser_id', t.advertiser_id, 'advertiser_name', p.username,
      'action_url', t.action_url, 'proof_required', t.proof_required,
      'daily_limit', t.daily_limit, 'total_limit', t.total_limit,
      'created_at', t.created_at
    ) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_task
    FROM tasks t
    LEFT JOIN profiles p ON p.id = t.advertiser_id
    WHERE t.advertiser_id IS NOT NULL
      AND (p_status IS NULL OR t.status = p_status);
  ELSE
    v_task := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object('ptc_campaigns', v_ptc, 'task_campaigns', v_task);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_all_campaigns(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_all_campaigns(text, text) TO authenticated;

-- ========== admin_pause_campaign ==========
CREATE OR REPLACE FUNCTION admin_pause_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type = 'ptc' THEN
    UPDATE ptc_ads SET status = 'paused', active = false
      WHERE id = p_campaign_id AND status IN ('active','pending');
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found or not pausable'; END IF;
  ELSIF p_type = 'task' THEN
    UPDATE tasks SET status = 'paused', active = false
      WHERE id = p_campaign_id AND status IN ('active','pending');
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found or not pausable'; END IF;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'admin_pause_campaign', p_type, p_campaign_id::text, jsonb_build_object('type', p_type));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_pause_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_pause_campaign(uuid, text) TO authenticated;

-- ========== admin_resume_campaign ==========
CREATE OR REPLACE FUNCTION admin_resume_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type = 'ptc' THEN
    UPDATE ptc_ads SET status = 'active', active = true
      WHERE id = p_campaign_id AND status = 'paused';
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found or not resumable'; END IF;
  ELSIF p_type = 'task' THEN
    UPDATE tasks SET status = 'active', active = true
      WHERE id = p_campaign_id AND status = 'paused';
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found or not resumable'; END IF;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'admin_resume_campaign', p_type, p_campaign_id::text, jsonb_build_object('type', p_type));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_resume_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_resume_campaign(uuid, text) TO authenticated;

-- ========== admin_stop_campaign ==========
CREATE OR REPLACE FUNCTION admin_stop_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_advertiser_id uuid;
  v_budget numeric(18,8);
  v_spent numeric(18,8);
  v_refund numeric(18,8);
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_type = 'ptc' THEN
    SELECT advertiser_id, budget, spent INTO v_advertiser_id, v_budget, v_spent
      FROM ptc_ads WHERE id = p_campaign_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE ptc_ads SET status = 'completed', active = false WHERE id = p_campaign_id;
  ELSIF p_type = 'task' THEN
    SELECT advertiser_id, budget, spent INTO v_advertiser_id, v_budget, v_spent
      FROM tasks WHERE id = p_campaign_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE tasks SET status = 'completed', active = false WHERE id = p_campaign_id;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;

  IF v_advertiser_id IS NOT NULL AND v_refund > 0 THEN
    UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = v_advertiser_id;
    v_ref := 'ad_refund:admin_stop:' || p_campaign_id::text;
    INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
      VALUES (v_advertiser_id, 'ad_refund', v_refund, p_type, p_campaign_id, v_ref,
        'Campaign stopped by admin — budget refund', 'completed')
      ON CONFLICT (reference) DO NOTHING;
  END IF;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'admin_stop_campaign', p_type, p_campaign_id::text,
      jsonb_build_object('type', p_type, 'refund', v_refund));
  RETURN jsonb_build_object('ok', true, 'refund', v_refund);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_stop_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_stop_campaign(uuid, text) TO authenticated;

-- ========== Enhanced admin_list_users with advertising_balance ==========
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
    'tasks_completed', p.tasks_completed, 'created_at', p.created_at
  ) ORDER BY p.created_at DESC), '[]'::jsonb)
  FROM profiles p
  WHERE p_search IS NULL OR p_search = ''
     OR p.username ILIKE '%' || p_search || '%'
     OR p.email ILIKE '%' || p_search || '%';
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;

-- ========== Enhanced admin_list_transactions with filters ==========
CREATE OR REPLACE FUNCTION admin_list_transactions(
  p_limit integer DEFAULT 200, p_offset integer DEFAULT 0,
  p_type text DEFAULT NULL, p_user_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'user_id', t.user_id, 'username', p.username,
    'type', t.type, 'amount', t.amount, 'status', t.status,
    'description', t.description, 'reference', t.reference,
    'created_at', t.created_at
  ) ORDER BY t.created_at DESC), '[]'::jsonb)
  FROM transactions t
  LEFT JOIN profiles p ON p.id = t.user_id
  WHERE (p_type IS NULL OR t.type = p_type)
    AND (p_user_id IS NULL OR t.user_id = p_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_transactions(integer, integer, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_transactions(integer, integer, text, uuid) TO authenticated;