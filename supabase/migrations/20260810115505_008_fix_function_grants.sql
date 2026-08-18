/*
# Fix function execute grants and trigger function search_path

1. Security changes
- REVOKE EXECUTE ON ALL SECURITY DEFINER functions FROM PUBLIC. PostgreSQL grants
  EXECUTE to PUBLIC by default, so REVOKE FROM anon alone was insufficient — anon still
  had execute via PUBLIC. After revoking from PUBLIC, only the explicit GRANT TO
  authenticated remains for user-facing functions.
- make_user_admin stays ungranted to anon/authenticated — only the service role can call it.
- Set SECURITY DEFINER SET search_path = public on touch_updated_at trigger function.

2. Notes
- User-facing functions (ptc_start, ptc_claim, task_submit, create_deposit,
  request_withdrawal, get_dashboard, qualify_referral) remain GRANTed TO authenticated.
- Admin functions (admin_*) remain GRANTed TO authenticated but check is_admin() internally.
- is_admin / is_staff_or_admin helpers remain GRANTed TO authenticated (used by admin functions).
*/

-- Fix trigger function search_path
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  new.updated_at := now();
  RETURN new;
END;
$$;

-- Revoke PUBLIC execute on ALL functions in public schema, then re-grant as needed.
-- This is safe because we explicitly GRANT EXECUTE TO authenticated on the ones users need.
REVOKE EXECUTE ON FUNCTION is_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION is_staff_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION is_staff_or_admin() TO authenticated;

REVOKE EXECUTE ON FUNCTION generate_referral_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION touch_updated_at() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION ptc_start(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION ptc_claim(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ptc_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION ptc_claim(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION create_deposit(numeric, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION approve_deposit(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION reject_deposit(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION request_withdrawal(numeric, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION approve_withdrawal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION reject_withdrawal(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_deposit(numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_deposit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_deposit(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION request_withdrawal(numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_withdrawal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_withdrawal(uuid, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION qualify_referral(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION qualify_referral(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_dashboard() TO authenticated;

REVOKE EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_set_user_status(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_update_settings(numeric, text, numeric, numeric, integer, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_audit_logs(integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_users(text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_deposits(text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_withdrawals(text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_transactions(integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_referrals(integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_list_tickets(text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_set_user_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_settings(numeric, text, numeric, numeric, integer, integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_audit_logs(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_users(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_deposits(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_withdrawals(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_transactions(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_referrals(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_list_tickets(text, integer, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION admin_create_ptc_ad(text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_update_ptc_ad(uuid, text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_create_task(text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_update_task(uuid, text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_delete_task(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_reply_ticket(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_ticket_set_status(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_stats() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_get_user_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_create_ptc_ad(text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_ptc_ad(uuid, text, text, text, text, numeric, integer, text, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_ptc_ad(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_create_task(text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_task(uuid, text, text, text, text, text, numeric, text, boolean, text, integer, integer, boolean, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_task(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_reply_ticket(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_ticket_set_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_user_detail(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION make_user_admin(uuid) FROM PUBLIC;
