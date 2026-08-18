/*
# Referral, dashboard, task review, admin management functions

1. Functions
- `qualify_referral(p_referred_id)` — checks app_settings.referral_qualification and, if
  met for the first time, marks the referral qualified and credits the referrer with
  app_settings.referral_reward via a `referral_reward` ledger transaction (unique ref).
- `get_dashboard()` — aggregated dashboard stats for the authenticated user, including
  today's earnings, total earnings, pending, withdrawn, ptc views, tasks completed,
  referral earnings, and a 7-day earnings series.
- `admin_review_task(p_completion_id, p_approve boolean, p_note text)` — admin reviews a
  pending task completion. On approve: credits reward via ledger (unique ref), increments
  profile balances/tasks_completed. On reject: marks rejected. Idempotent via completion
  status check + unique ledger reference.
- `admin_set_user_status(p_user_id, p_status text)` — admin suspends/activates a user.
  Prevents an admin from locking themselves out.
- `admin_update_settings(...)` — admin updates app_settings.
- `admin_list_audit_logs(p_limit int)` — admin reads audit logs.
- `admin_list_users(p_search text, p_limit int, p_offset int)` — admin lists/searches users.
- `admin_list_deposits(p_status text, p_limit int, p_offset int)` and similar for
  withdrawals, transactions, referrals, tickets — admin-scoped reads.

2. Security
- All SECURITY DEFINER, search_path = public. Admin functions check is_admin().
- Actor always from auth.uid().

3. Notes
- qualify_referral is idempotent (qualified flag + unique ledger ref).
*/

-- ---------- qualify_referral ----------
CREATE OR REPLACE FUNCTION qualify_referral(p_referred_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_referral referrals%ROWTYPE;
  v_settings app_settings%ROWTYPE;
  v_qualify boolean := false;
  v_referred_profile profiles%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_settings FROM app_settings WHERE id = 1;

  SELECT * INTO v_referral FROM referrals WHERE referred_id = p_referred_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_referral.qualified THEN RETURN; END IF;

  SELECT * INTO v_referred_profile FROM profiles WHERE id = p_referred_id;
  IF NOT FOUND THEN RETURN; END IF;

  CASE v_settings.referral_qualification
    WHEN 'signup' THEN
      v_qualify := true;
    WHEN 'first_ptc' THEN
      v_qualify := v_referred_profile.ptc_views > 0;
    WHEN 'first_task' THEN
      v_qualify := v_referred_profile.tasks_completed > 0;
    WHEN 'first_deposit' THEN
      v_qualify := v_referred_profile.total_deposited > 0;
    ELSE
      v_qualify := false;
  END CASE;

  IF NOT v_qualify THEN RETURN; END IF;

  UPDATE referrals SET qualified = true, qualified_at = now(), reward_amount = v_settings.referral_reward
    WHERE id = v_referral.id;

  v_ref := 'referral:' || v_referral.id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (v_referral.referrer_id, 'referral_reward', v_settings.referral_reward, 'referral', v_referral.id, v_ref, 'Referral reward', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NOT NULL THEN
    UPDATE profiles
      SET available_balance = available_balance + v_settings.referral_reward,
          total_earned = total_earned + v_settings.referral_reward
      WHERE id = v_referral.referrer_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION qualify_referral(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION qualify_referral(uuid) TO authenticated;

-- ---------- get_dashboard ----------
CREATE OR REPLACE FUNCTION get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_today_earned numeric;
  v_referral_earned numeric;
  v_pending_count integer;
  v_series jsonb;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_today_earned FROM transactions
    WHERE user_id = auth.uid() AND amount > 0 AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_referral_earned FROM transactions
    WHERE user_id = auth.uid() AND type = 'referral_reward' AND status = 'completed';

  SELECT count(*) INTO v_pending_count FROM withdrawals WHERE user_id = auth.uid() AND status = 'pending';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d, 'amount', coalesce(amt, 0)) ORDER BY d), '[]'::jsonb) INTO v_series
    FROM (
      SELECT generate_series(current_date - interval '6 days', current_date, '1 day')::date AS d
    ) days
    LEFT JOIN LATERAL (
      SELECT sum(amount) AS amt FROM transactions
        WHERE user_id = auth.uid() AND amount > 0 AND date_trunc('day', created_at) = d::timestamptz
    ) s ON true;

  RETURN jsonb_build_object(
    'available_balance', v_profile.available_balance,
    'pending_balance', v_profile.pending_balance,
    'total_earned', v_profile.total_earned,
    'total_withdrawn', v_profile.total_withdrawn,
    'total_deposited', v_profile.total_deposited,
    'today_earned', v_today_earned,
    'referral_earned', v_referral_earned,
    'ptc_views', v_profile.ptc_views,
    'tasks_completed', v_profile.tasks_completed,
    'pending_withdrawals', v_pending_count,
    'role', v_profile.role,
    'status', v_profile.status,
    'earnings_series', v_series
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_dashboard() FROM anon;
GRANT EXECUTE ON FUNCTION get_dashboard() TO authenticated;

-- ---------- admin_review_task ----------
CREATE OR REPLACE FUNCTION admin_review_task(p_completion_id uuid, p_approve boolean, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_completion FROM task_completions WHERE id = p_completion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task completion not found'; END IF;
  IF v_completion.status != 'pending' THEN RAISE EXCEPTION 'Task already reviewed'; END IF;

  IF p_approve THEN
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
      VALUES (v_completion.user_id, 'task_reward', v_completion.reward, 'task_completion', v_completion.id, v_ref, 'Task reward (approved)', 'completed')
      ON CONFLICT (reference) DO NOTHING
      RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET available_balance = available_balance + v_completion.reward,
            total_earned = total_earned + v_completion.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = v_completion.user_id;
      PERFORM qualify_referral(v_completion.user_id);
    END IF;

    UPDATE task_completions SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'approve_task', 'task_completion', p_completion_id::text, jsonb_build_object('reward', v_completion.reward));
    RETURN jsonb_build_object('ok', true, 'status', 'approved');
  ELSE
    UPDATE task_completions SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'reject_task', 'task_completion', p_completion_id::text, jsonb_build_object('note', p_note));
    RETURN jsonb_build_object('ok', true, 'status', 'rejected');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) TO authenticated;

-- ---------- admin_set_user_status ----------
CREATE OR REPLACE FUNCTION admin_set_user_status(p_user_id uuid, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('active','suspended','banned') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_user_id = auth.uid() AND p_status != 'active' THEN
    RAISE EXCEPTION 'You cannot suspend your own account';
  END IF;
  UPDATE profiles SET status = p_status WHERE id = p_user_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'set_user_status', 'profile', p_user_id::text, jsonb_build_object('status', p_status));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_set_user_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_set_user_status(uuid, text) TO authenticated;

-- ---------- admin_update_settings ----------
CREATE OR REPLACE FUNCTION admin_update_settings(
  p_referral_reward numeric,
  p_referral_qualification text,
  p_min_withdrawal numeric,
  p_max_withdrawal numeric,
  p_withdrawal_cooldown_minutes integer,
  p_ptc_daily_limit_per_ad integer,
  p_task_daily_limit integer,
  p_platform_name text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE app_settings SET
    referral_reward = COALESCE(p_referral_reward, referral_reward),
    referral_qualification = COALESCE(p_referral_qualification, referral_qualification),
    min_withdrawal = COALESCE(p_min_withdrawal, min_withdrawal),
    max_withdrawal = COALESCE(p_max_withdrawal, max_withdrawal),
    withdrawal_cooldown_minutes = COALESCE(p_withdrawal_cooldown_minutes, withdrawal_cooldown_minutes),
    ptc_daily_limit_per_ad = COALESCE(p_ptc_daily_limit_per_ad, ptc_daily_limit_per_ad),
    task_daily_limit = COALESCE(p_task_daily_limit, task_daily_limit),
    platform_name = COALESCE(p_platform_name, platform_name),
    updated_at = now()
    WHERE id = 1;
  INSERT INTO audit_logs (actor_id, action, target_type, details)
    VALUES (auth.uid(), 'update_settings', 'app_settings', jsonb_build_object('platform_name', p_platform_name));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_settings(numeric, text, numeric, numeric, integer, integer, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_settings(numeric, text, numeric, numeric, integer, integer, integer, text) TO authenticated;

-- ---------- admin_list_audit_logs ----------
CREATE OR REPLACE FUNCTION admin_list_audit_logs(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id, 'actor_id', a.actor_id, 'action', a.action,
    'target_type', a.target_type, 'target_id', a.target_id,
    'details', a.details, 'created_at', a.created_at,
    'actor_username', p.username
  ) ORDER BY a.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM audit_logs a
    LEFT JOIN profiles p ON p.id = a.actor_id
    LIMIT GREATEST(COALESCE(p_limit, 100), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_audit_logs(integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_audit_logs(integer, integer) TO authenticated;

-- ---------- admin_list_users ----------
CREATE OR REPLACE FUNCTION admin_list_users(p_search text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id, 'username', p.username, 'email', p.email, 'full_name', p.full_name,
    'country', p.country, 'role', p.role, 'status', p.status,
    'available_balance', p.available_balance, 'total_earned', p.total_earned,
    'total_withdrawn', p.total_withdrawn, 'total_deposited', p.total_deposited,
    'ptc_views', p.ptc_views, 'tasks_completed', p.tasks_completed,
    'created_at', p.created_at
  ) ORDER BY p.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM profiles p
    WHERE p_search IS NULL
       OR p.username ILIKE '%' || p_search || '%'
       OR p.email ILIKE '%' || p_search || '%'
    LIMIT GREATEST(COALESCE(p_limit, 50), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;

-- ---------- admin_list_deposits ----------
CREATE OR REPLACE FUNCTION admin_list_deposits(p_status text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', d.id, 'user_id', d.user_id, 'username', p.username, 'email', p.email,
    'amount', d.amount, 'payment_method', d.payment_method, 'status', d.status,
    'admin_note', d.admin_note, 'created_at', d.created_at, 'reviewed_at', d.reviewed_at
  ) ORDER BY d.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM deposits d
    LEFT JOIN profiles p ON p.id = d.user_id
    WHERE p_status IS NULL OR d.status = p_status
    LIMIT GREATEST(COALESCE(p_limit, 50), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_deposits(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_deposits(text, integer, integer) TO authenticated;

-- ---------- admin_list_withdrawals ----------
CREATE OR REPLACE FUNCTION admin_list_withdrawals(p_status text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', w.id, 'user_id', w.user_id, 'username', p.username, 'email', p.email,
    'amount', w.amount, 'withdrawal_method', w.withdrawal_method, 'destination', w.destination,
    'status', w.status, 'admin_note', w.admin_note, 'created_at', w.created_at, 'reviewed_at', w.reviewed_at
  ) ORDER BY w.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM withdrawals w
    LEFT JOIN profiles p ON p.id = w.user_id
    WHERE p_status IS NULL OR w.status = p_status
    LIMIT GREATEST(COALESCE(p_limit, 50), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_withdrawals(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_withdrawals(text, integer, integer) TO authenticated;

-- ---------- admin_list_transactions ----------
CREATE OR REPLACE FUNCTION admin_list_transactions(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'user_id', t.user_id, 'username', p.username,
    'type', t.type, 'amount', t.amount, 'status', t.status,
    'description', t.description, 'reference', t.reference, 'created_at', t.created_at
  ) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM transactions t
    LEFT JOIN profiles p ON p.id = t.user_id
    LIMIT GREATEST(COALESCE(p_limit, 100), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_transactions(integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_transactions(integer, integer) TO authenticated;

-- ---------- admin_list_referrals ----------
CREATE OR REPLACE FUNCTION admin_list_referrals(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id, 'referrer_id', r.referrer_id, 'referrer', pu.username,
    'referred_id', r.referred_id, 'referred', pu2.username,
    'qualified', r.qualified, 'reward_amount', r.reward_amount,
    'created_at', r.created_at, 'qualified_at', r.qualified_at
  ) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_rows
    FROM referrals r
    LEFT JOIN profiles pu ON pu.id = r.referrer_id
    LEFT JOIN profiles pu2 ON pu2.id = r.referred_id
    LIMIT GREATEST(COALESCE(p_limit, 100), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_referrals(integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_referrals(integer, integer) TO authenticated;

-- ---------- admin_list_tickets ----------
CREATE OR REPLACE FUNCTION admin_list_tickets(p_status text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'user_id', t.user_id, 'username', p.username,
    'subject', t.subject, 'category', t.category, 'priority', t.priority,
    'status', t.status, 'created_at', t.created_at, 'updated_at', t.updated_at
  ) ORDER BY t.updated_at DESC), '[]'::jsonb) INTO v_rows
    FROM support_tickets t
    LEFT JOIN profiles p ON p.id = t.user_id
    WHERE p_status IS NULL OR t.status = p_status
    LIMIT GREATEST(COALESCE(p_limit, 50), 1)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_tickets(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_tickets(text, integer, integer) TO authenticated;
