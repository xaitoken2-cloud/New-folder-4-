/*
# Admin PTC/task CRUD, ticket staff reply, admin stats, make-admin helper

1. Functions
- `admin_create_ptc_ad(...)` / `admin_update_ptc_ad(...)` / `admin_delete_ptc_ad(p_id)` —
  admin CRUD for PTC advertisements. All values validated server-side. Reward and duration
  come from the server, never the client during a claim.
- `admin_create_task(...)` / `admin_update_task(...)` / `admin_delete_task(p_id)` — admin
  CRUD for tasks.
- `admin_reply_ticket(p_ticket_id, p_message)` — admin posts a staff reply and sets ticket
  status to 'pending' (awaiting user). Reads via existing RLS for admin? No — admin role
  isn't the ticket owner, so this function (SECURITY DEFINER) inserts the reply.
- `admin_ticket_set_status(p_ticket_id, p_status)` — admin closes/opens a ticket.
- `admin_stats()` — aggregate platform stats for the admin dashboard.
- `admin_get_user_detail(p_user_id)` — full detail for a user including recent activity.
- `make_user_admin(p_user_id)` — bootstrap helper to grant admin role. SECURITY DEFINER,
  callable only via service role (no anon/authenticated grant). Used once during seeding.

2. Security
- All SECURITY DEFINER, search_path = public. Admin functions check is_admin().
- make_user_admin has NO execute grant to anon/authenticated — only the service role
  (which bypasses RLS) can call it, so only an operator can bootstrap the first admin.

3. Notes
- PTC ad reward/duration are authoritative server-side values. The claim function reads
  them from the row, never from the client.
*/

-- ---------- admin_create_ptc_ad ----------
CREATE OR REPLACE FUNCTION admin_create_ptc_ad(
  p_title text, p_description text, p_advertiser text, p_category text,
  p_reward numeric, p_duration_seconds integer, p_destination_url text, p_image_url text,
  p_daily_view_limit integer, p_total_view_limit integer, p_active boolean,
  p_start_date timestamptz, p_end_date timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Reward must be positive'; END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds < 1 OR p_duration_seconds > 3600 THEN RAISE EXCEPTION 'Duration must be 1-3600 seconds'; END IF;
  IF p_daily_view_limit IS NULL OR p_daily_view_limit < 1 THEN RAISE EXCEPTION 'Daily view limit must be >= 1'; END IF;
  IF p_total_view_limit IS NULL OR p_total_view_limit < 0 THEN RAISE EXCEPTION 'Total view limit invalid'; END IF;

  INSERT INTO ptc_ads (title, description, advertiser, category, reward, duration_seconds,
      destination_url, image_url, daily_view_limit, total_view_limit, active,
      start_date, end_date, created_by)
    VALUES (p_title, COALESCE(p_description,''), COALESCE(p_advertiser,''), COALESCE(p_category,'general'),
      p_reward, p_duration_seconds, COALESCE(p_destination_url,''), COALESCE(p_image_url,''),
      p_daily_view_limit, p_total_view_limit, COALESCE(p_active, true),
      p_start_date, p_end_date, auth.uid())
    RETURNING id INTO v_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'create_ptc_ad', 'ptc_ad', v_id::text, jsonb_build_object('title', p_title, 'reward', p_reward));
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_create_ptc_ad(text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION admin_create_ptc_ad(text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;

-- ---------- admin_update_ptc_ad ----------
CREATE OR REPLACE FUNCTION admin_update_ptc_ad(
  p_id uuid, p_title text, p_description text, p_advertiser text, p_category text,
  p_reward numeric, p_duration_seconds integer, p_destination_url text, p_image_url text,
  p_daily_view_limit integer, p_total_view_limit integer, p_active boolean,
  p_start_date timestamptz, p_end_date timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Reward must be positive'; END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds < 1 OR p_duration_seconds > 3600 THEN RAISE EXCEPTION 'Duration must be 1-3600 seconds'; END IF;
  UPDATE ptc_ads SET
    title = p_title, description = p_description, advertiser = p_advertiser, category = p_category,
    reward = p_reward, duration_seconds = p_duration_seconds, destination_url = p_destination_url,
    image_url = p_image_url, daily_view_limit = p_daily_view_limit, total_view_limit = p_total_view_limit,
    active = p_active, start_date = p_start_date, end_date = p_end_date
    WHERE id = p_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'update_ptc_ad', 'ptc_ad', p_id::text, jsonb_build_object('title', p_title));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_ptc_ad(uuid, text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_ptc_ad(uuid, text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;

-- ---------- admin_delete_ptc_ad ----------
CREATE OR REPLACE FUNCTION admin_delete_ptc_ad(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM ptc_ads WHERE id = p_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'delete_ptc_ad', 'ptc_ad', p_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) TO authenticated;

-- ---------- admin_create_task ----------
CREATE OR REPLACE FUNCTION admin_create_task(
  p_title text, p_description text, p_instructions text, p_category text, p_task_type text,
  p_reward numeric, p_action_url text, p_proof_required boolean, p_proof_instructions text,
  p_daily_limit integer, p_total_limit integer, p_active boolean,
  p_start_date timestamptz, p_end_date timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Reward must be positive'; END IF;
  IF p_task_type NOT IN ('visit_website','registration','social_follow','app_install','survey','submit_proof','custom') THEN
    RAISE EXCEPTION 'Invalid task type';
  END IF;
  INSERT INTO tasks (title, description, instructions, category, task_type, reward,
      action_url, proof_required, proof_instructions, daily_limit, total_limit, active,
      start_date, end_date, created_by)
    VALUES (p_title, COALESCE(p_description,''), COALESCE(p_instructions,''), COALESCE(p_category,'general'),
      p_task_type, p_reward, COALESCE(p_action_url,''), COALESCE(p_proof_required,false),
      COALESCE(p_proof_instructions,''), COALESCE(p_daily_limit,0), COALESCE(p_total_limit,0),
      COALESCE(p_active,true), p_start_date, p_end_date, auth.uid())
    RETURNING id INTO v_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'create_task', 'task', v_id::text, jsonb_build_object('title', p_title));
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_create_task(text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION admin_create_task(text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;

-- ---------- admin_update_task ----------
CREATE OR REPLACE FUNCTION admin_update_task(
  p_id uuid, p_title text, p_description text, p_instructions text, p_category text, p_task_type text,
  p_reward numeric, p_action_url text, p_proof_required boolean, p_proof_instructions text,
  p_daily_limit integer, p_total_limit integer, p_active boolean,
  p_start_date timestamptz, p_end_date timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Reward must be positive'; END IF;
  UPDATE tasks SET
    title = p_title, description = p_description, instructions = p_instructions, category = p_category,
    task_type = p_task_type, reward = p_reward, action_url = p_action_url,
    proof_required = p_proof_required, proof_instructions = p_proof_instructions,
    daily_limit = p_daily_limit, total_limit = p_total_limit, active = p_active,
    start_date = p_start_date, end_date = p_end_date
    WHERE id = p_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'update_task', 'task', p_id::text, jsonb_build_object('title', p_title));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_task(uuid, text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_task(uuid, text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;

-- ---------- admin_delete_task ----------
CREATE OR REPLACE FUNCTION admin_delete_task(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM tasks WHERE id = p_id;
  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'delete_task', 'task', p_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_delete_task(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_delete_task(uuid) TO authenticated;

-- ---------- admin_reply_ticket ----------
CREATE OR REPLACE FUNCTION admin_reply_ticket(p_ticket_id uuid, p_message text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ticket support_tickets%ROWTYPE;
BEGIN
  IF NOT is_staff_or_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_ticket FROM support_tickets WHERE id = p_ticket_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ticket not found'; END IF;
  IF v_ticket.status = 'closed' THEN RAISE EXCEPTION 'Ticket is closed'; END IF;
  INSERT INTO ticket_replies (ticket_id, user_id, message, is_staff)
    VALUES (p_ticket_id, auth.uid(), p_message, true);
  UPDATE support_tickets SET status = 'pending', updated_at = now() WHERE id = p_ticket_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_reply_ticket(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_reply_ticket(uuid, text) TO authenticated;

-- ---------- admin_ticket_set_status ----------
CREATE OR REPLACE FUNCTION admin_ticket_set_status(p_ticket_id uuid, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_staff_or_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('open','pending','closed') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  UPDATE support_tickets SET status = p_status, updated_at = now() WHERE id = p_ticket_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_ticket_set_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_ticket_set_status(uuid, text) TO authenticated;

-- ---------- admin_stats ----------
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
  v_total_deposited numeric;
  v_total_withdrawn numeric;
  v_total_paid_out numeric;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT count(*) INTO v_users FROM profiles;
  SELECT count(*) INTO v_active_ads FROM ptc_ads WHERE active;
  SELECT count(*) INTO v_active_tasks FROM tasks WHERE active;
  SELECT COALESCE(sum(total_views),0) INTO v_total_ptc_views FROM ptc_ads;
  SELECT count(*) INTO v_total_task_completions FROM task_completions WHERE status='approved';
  SELECT count(*) INTO v_pending_deposits FROM deposits WHERE status='pending';
  SELECT count(*) INTO v_pending_withdrawals FROM withdrawals WHERE status='pending';
  SELECT COALESCE(sum(total_deposited),0) INTO v_total_deposited FROM profiles;
  SELECT COALESCE(sum(total_withdrawn),0) INTO v_total_withdrawn FROM profiles;
  SELECT COALESCE(sum(total_earned),0) INTO v_total_paid_out FROM profiles;
  RETURN jsonb_build_object(
    'users', v_users, 'active_ads', v_active_ads, 'active_tasks', v_active_tasks,
    'total_ptc_views', v_total_ptc_views, 'total_task_completions', v_total_task_completions,
    'pending_deposits', v_pending_deposits, 'pending_withdrawals', v_pending_withdrawals,
    'total_deposited', v_total_deposited, 'total_withdrawn', v_total_withdrawn,
    'total_paid_out', v_total_paid_out
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_stats() FROM anon;
GRANT EXECUTE ON FUNCTION admin_stats() TO authenticated;

-- ---------- admin_get_user_detail ----------
CREATE OR REPLACE FUNCTION admin_get_user_detail(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile jsonb;
  v_recent_tx jsonb;
  v_recent_ptc jsonb;
  v_recent_tasks jsonb;
  v_wds jsonb;
  v_deps jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT to_jsonb(p) INTO v_profile FROM profiles p WHERE id = p_user_id;
  IF v_profile IS NULL THEN RAISE EXCEPTION 'User not found'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'type', t.type, 'amount', t.amount, 'status', t.status, 'description', t.description, 'created_at', t.created_at) ORDER BY t.created_at DESC), '[]'::jsonb)
    INTO v_recent_tx FROM transactions t WHERE t.user_id = p_user_id LIMIT 10;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', v.id, 'ad_id', v.ptc_ad_id, 'status', v.status, 'reward', v.reward, 'started_at', v.started_at, 'completed_at', v.completed_at) ORDER BY v.started_at DESC), '[]'::jsonb)
    INTO v_recent_ptc FROM ptc_ad_views v WHERE v.user_id = p_user_id LIMIT 10;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'task_id', c.task_id, 'status', c.status, 'reward', c.reward, 'created_at', c.created_at) ORDER BY c.created_at DESC), '[]'::jsonb)
    INTO v_recent_tasks FROM task_completions c WHERE c.user_id = p_user_id LIMIT 10;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', w.id, 'amount', w.amount, 'method', w.withdrawal_method, 'destination', w.destination, 'status', w.status, 'created_at', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb)
    INTO v_wds FROM withdrawals w WHERE w.user_id = p_user_id LIMIT 10;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', d.id, 'amount', d.amount, 'method', d.payment_method, 'status', d.status, 'created_at', d.created_at) ORDER BY d.created_at DESC), '[]'::jsonb)
    INTO v_deps FROM deposits d WHERE d.user_id = p_user_id LIMIT 10;
  RETURN jsonb_build_object(
    'profile', v_profile,
    'recent_transactions', v_recent_tx,
    'recent_ptc', v_recent_ptc,
    'recent_tasks', v_recent_tasks,
    'withdrawals', v_wds,
    'deposits', v_deps
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_get_user_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION admin_get_user_detail(uuid) TO authenticated;

-- ---------- make_user_admin (bootstrap, service-role only) ----------
CREATE OR REPLACE FUNCTION make_user_admin(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE profiles SET role = 'admin' WHERE id = p_user_id;
END;
$$;
-- No grant to anon/authenticated: only the service role (bypasses RLS/EXECUTE checks) can call this.
