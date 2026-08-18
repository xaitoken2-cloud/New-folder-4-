-- ========== Add ban columns to profiles ==========
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'ban_reason') THEN
    ALTER TABLE profiles ADD COLUMN ban_reason text NOT NULL DEFAULT '';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'banned_at') THEN
    ALTER TABLE profiles ADD COLUMN banned_at timestamptz;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'banned_by') THEN
    ALTER TABLE profiles ADD COLUMN banned_by uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ========== admin_ban_user ==========
CREATE OR REPLACE FUNCTION admin_ban_user(p_user_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target profiles%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_user_id = auth.uid() THEN RAISE EXCEPTION 'You cannot ban yourself'; END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN RAISE EXCEPTION 'Ban reason is required'; END IF;

  SELECT * INTO v_target FROM profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
  IF v_target.role = 'admin' THEN RAISE EXCEPTION 'Cannot ban an admin'; END IF;

  UPDATE profiles
    SET status = 'banned',
        ban_reason = p_reason,
        banned_at = now(),
        banned_by = auth.uid()
    WHERE id = p_user_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'ban_user', 'profile', p_user_id::text,
      jsonb_build_object('reason', p_reason, 'username', v_target.username));

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_ban_user(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_ban_user(uuid, text) TO authenticated;

-- ========== admin_unban_user ==========
CREATE OR REPLACE FUNCTION admin_unban_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target profiles%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_target FROM profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
  IF v_target.status != 'banned' THEN RAISE EXCEPTION 'User is not banned'; END IF;

  UPDATE profiles
    SET status = 'active',
        ban_reason = '',
        banned_at = NULL,
        banned_by = NULL
    WHERE id = p_user_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'unban_user', 'profile', p_user_id::text,
      jsonb_build_object('username', v_target.username, 'previous_reason', v_target.ban_reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_unban_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_unban_user(uuid) TO authenticated;

-- ========== Updated admin_delete_ptc_ad with budget refund ==========
CREATE OR REPLACE FUNCTION admin_delete_ptc_ad(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ad ptc_ads%ROWTYPE;
  v_refund numeric(18,8);
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_ad FROM ptc_ads WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;

  -- Refund unspent budget to advertiser if this is a campaign
  IF v_ad.advertiser_id IS NOT NULL THEN
    v_refund := v_ad.budget - v_ad.spent;
    IF v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = v_ad.advertiser_id;
      v_ref := 'ad_refund:admin_delete_ptc:' || p_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (v_ad.advertiser_id, 'ad_refund', v_refund, 'ptc_ad', p_id, v_ref,
          'PTC ad deleted by admin — budget refund', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  END IF;

  DELETE FROM ptc_ads WHERE id = p_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'delete_ptc_ad', 'ptc_ad', p_id::text,
      jsonb_build_object('title', v_ad.title, 'refund', v_refund));

  RETURN jsonb_build_object('ok', true, 'refund', v_refund);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) TO authenticated;

-- ========== Updated admin_delete_task with budget refund ==========
CREATE OR REPLACE FUNCTION admin_delete_task(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_refund numeric(18,8);
  v_ref text;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_task FROM tasks WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;

  -- Refund unspent budget to advertiser if this is a campaign
  IF v_task.advertiser_id IS NOT NULL THEN
    v_refund := v_task.budget - v_task.spent;
    IF v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = v_task.advertiser_id;
      v_ref := 'ad_refund:admin_delete_task:' || p_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (v_task.advertiser_id, 'ad_refund', v_refund, 'task', p_id, v_ref,
          'Task deleted by admin — budget refund', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  END IF;

  DELETE FROM tasks WHERE id = p_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'delete_task', 'task', p_id::text,
      jsonb_build_object('title', v_task.title, 'refund', v_refund));

  RETURN jsonb_build_object('ok', true, 'refund', v_refund);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_delete_task(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_delete_task(uuid) TO authenticated;

-- ========== Updated admin_list_users with ban fields ==========
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
    'ban_reason', p.ban_reason, 'banned_at', p.banned_at, 'banned_by', p.banned_by
  ) ORDER BY p.created_at DESC), '[]'::jsonb)
  FROM profiles p
  WHERE p_search IS NULL OR p_search = ''
     OR p.username ILIKE '%' || p_search || '%'
     OR p.email ILIKE '%' || p_search || '%';
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;
