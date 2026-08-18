import { supabase } from './supabase';
import type {
  Profile, Transaction, PtcAd, PtcAdView, Task, TaskCompletion,
  Deposit, Withdrawal, ReferralRow, SupportTicket, TicketReply,
  AppSettings, DashboardData, PtcStartResult, PtcClaimResult, PtcHeartbeatResult,
  AdminUserRow, AdminDepositRow, AdminWithdrawalRow, AdminTransactionRow,
  AdminReferralRow, AdminTicketRow, AuditLog, AdminStats,
  AdDashboardData, AdCampaignsResult, AdminPendingCampaignsResult,
  AdminAdvertiserRow, AdminAllCampaignsResult,
  Offer, OfferStartResult, OfferSession, OfferSessionDetail,
  OfferAdminStats, OfferAdminSession, OfferProviderAdmin,
  XcRecipientLookup, XcTransferResult, XcTransferHistoryRow, AdminXcTransferRow,
  PublicProfile, FollowListRow, FollowResult,
} from '@/types';

export function getErrorMessage(err: unknown, fallback: string): string {
  if (err instanceof Error) return err.message;
  if (
    typeof err === 'object' &&
    err !== null &&
    'message' in err &&
    typeof (err as { message?: unknown }).message === 'string'
  ) {
    return (err as { message: string }).message;
  }
  return fallback;
}

/* ---------- Auth ---------- */

export interface SignUpInput {
  email: string;
  password: string;
  username: string;
  fullName: string;
  referralCode?: string;
}

export async function signUp(input: SignUpInput) {
  const { data, error } = await supabase.auth.signUp({
    email: input.email,
    password: input.password,
    options: {
      data: {
        username: input.username,
        full_name: input.fullName,
        ...(input.referralCode ? { referral_code: input.referralCode } : {}),
      },
    },
  });
  if (error) throw error;
  return data;
}

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function requestPasswordReset(email: string) {
  const { data, error } = await supabase.auth.resetPasswordForEmail(email);
  if (error) throw error;
  return data;
}

export async function updatePassword(newPassword: string) {
  const { data, error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) throw error;
  return data;
}

export async function changePassword(currentPassword: string, newPassword: string): Promise<void> {
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/change-password`;
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Not authenticated');
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ currentPassword, newPassword }),
  });
  const result = await response.json().catch(() => ({ error: 'Failed to change password' }));
  if (!response.ok) {
    throw new Error(result.error || 'Failed to change password');
  }
}

/* ---------- Profile ---------- */

export async function getProfile(): Promise<Profile | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .maybeSingle();
  if (error) throw error;
  return data as Profile | null;
}

export async function updateProfile(updates: { full_name?: string; avatar_url?: string }) {
  const { data, error } = await supabase
    .from('profiles')
    .update(updates)
    .select()
    .maybeSingle();
  if (error) throw error;
  return data as Profile;
}

/* ---------- Dashboard ---------- */

export async function getDashboard(): Promise<DashboardData> {
  const { data, error } = await supabase.rpc('get_dashboard');
  if (error) throw error;
  return data as DashboardData;
}

/* ---------- PTC ---------- */

export async function listPtcAds(): Promise<PtcAd[]> {
  const { data, error } = await supabase.rpc('list_available_ptc_ads');
  if (error) throw error;
  return (data as PtcAd[]) ?? [];
}

export async function getPtcAd(id: string): Promise<PtcAd | null> {
  const { data, error } = await supabase.rpc('get_available_ptc_ad', { p_ad_id: id });
  if (error) throw error;
  return (data as PtcAd) ?? null;
}

export async function getMyPtcViews(): Promise<PtcAdView[]> {
  const { data, error } = await supabase
    .from('ptc_ad_views')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) throw error;
  return data as PtcAdView[];
}

export async function startPtcView(adId: string): Promise<PtcStartResult> {
  const { data, error } = await supabase.rpc('ptc_start', { p_ad_id: adId });
  if (error) throw error;
  return data as PtcStartResult;
}

export async function heartbeatPtcView(viewId: string, sessionToken: string): Promise<PtcHeartbeatResult> {
  const { data, error } = await supabase.rpc('ptc_heartbeat', { p_view_id: viewId, p_session_token: sessionToken });
  if (error) throw error;
  return data as PtcHeartbeatResult;
}

export async function claimPtcView(viewId: string): Promise<PtcClaimResult> {
  const { data, error } = await supabase.rpc('ptc_claim', { p_view_id: viewId });
  if (error) throw error;
  return data as PtcClaimResult;
}

/* ---------- Tasks ---------- */

export async function listTasks(): Promise<Task[]> {
  const { data, error } = await supabase.rpc('list_available_tasks');
  if (error) throw error;
  return (data as Task[]) ?? [];
}

export async function getTask(id: string): Promise<Task | null> {
  const { data, error } = await supabase.rpc('get_available_task', { p_task_id: id });
  if (error) throw error;
  return (data as Task) ?? null;
}

export async function getMyTaskCompletions(): Promise<TaskCompletion[]> {
  const { data, error } = await supabase
    .from('task_completions')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) throw error;
  return data as TaskCompletion[];
}

export async function submitTask(taskId: string, proofText: string) {
  const { data, error } = await supabase.rpc('task_submit', {
    p_task_id: taskId,
    p_proof_text: proofText,
  });
  if (error) throw error;
  return data as { ok: boolean; status: string; completion_id: string; reward?: number };
}

/* ---------- XC Conversion ---------- */

export async function convertUsdToXc(amountUsd: number): Promise<{
  ok: boolean;
  usd_amount: number;
  xc_amount: number;
  xc_balance: number;
  available_balance: number;
}> {
  const { data, error } = await supabase.rpc('convert_usd_to_xc', { p_amount_usd: amountUsd });
  if (error) throw error;
  return data;
}

/* ---------- XC Transfers ---------- */

export async function xcLookupRecipient(query: string): Promise<XcRecipientLookup> {
  const { data, error } = await supabase.rpc('xc_lookup_recipient', { p_query: query });
  if (error) throw error;
  return data as XcRecipientLookup;
}

export async function xcTransfer(recipientQuery: string, amount: number, clientReference: string): Promise<XcTransferResult> {
  const { data, error } = await supabase.rpc('xc_transfer', {
    p_recipient_query: recipientQuery, p_amount: amount, p_client_reference: clientReference,
  });
  if (error) throw error;
  return data as XcTransferResult;
}

export async function listXcTransfers(limit = 50, offset = 0): Promise<XcTransferHistoryRow[]> {
  const { data, error } = await supabase.rpc('list_xc_transfers', { p_limit: limit, p_offset: offset });
  if (error) throw error;
  return data as XcTransferHistoryRow[];
}

/* ---------- Public Profile + Follow System ---------- */

export async function getPublicProfile(username: string): Promise<PublicProfile> {
  const { data, error } = await supabase.rpc('get_public_profile', { p_username: username });
  if (error) throw error;
  return data as PublicProfile;
}

export async function followUser(username: string): Promise<FollowResult> {
  const { data, error } = await supabase.rpc('follow_user', { p_username: username });
  if (error) throw error;
  return data as FollowResult;
}

export async function unfollowUser(username: string): Promise<FollowResult> {
  const { data, error } = await supabase.rpc('unfollow_user', { p_username: username });
  if (error) throw error;
  return data as FollowResult;
}

export async function listFollowers(username: string, limit = 50, offset = 0): Promise<FollowListRow[]> {
  const { data, error } = await supabase.rpc('list_followers', {
    p_username: username, p_limit: limit, p_offset: offset,
  });
  if (error) throw error;
  return data as FollowListRow[];
}

export async function listFollowing(username: string, limit = 50, offset = 0): Promise<FollowListRow[]> {
  const { data, error } = await supabase.rpc('list_following', {
    p_username: username, p_limit: limit, p_offset: offset,
  });
  if (error) throw error;
  return data as FollowListRow[];
}

export async function adminListXcTransfers(limit = 200, offset = 0): Promise<AdminXcTransferRow[]> {
  const { data, error } = await supabase.rpc('admin_list_xc_transfers', { p_limit: limit, p_offset: offset });
  if (error) throw error;
  return data as AdminXcTransferRow[];
}

/* ---------- Transactions ---------- */

export async function listTransactions(filter?: string, page = 1, perPage = 20) {
  let query = supabase.from('transactions').select('*', { count: 'exact' });
  if (filter === 'earnings') {
    query = query.in('type', ['ptc_reward', 'task_reward', 'referral_reward', 'offer_reward']);
  } else if (filter === 'deposits') {
    query = query.eq('type', 'deposit');
  } else if (filter === 'withdrawals') {
    query = query.in('type', ['withdrawal', 'withdrawal_refund']);
  } else if (filter === 'ptc') {
    query = query.eq('type', 'ptc_reward');
  } else if (filter === 'tasks') {
    query = query.eq('type', 'task_reward');
  } else if (filter === 'referrals') {
    query = query.eq('type', 'referral_reward');
  }
  const from = (page - 1) * perPage;
  const { data, error, count } = await query
    .order('created_at', { ascending: false })
    .range(from, from + perPage - 1);
  if (error) throw error;
  return { data: data as Transaction[], total: count ?? 0 };
}

/* ---------- Deposits ---------- */

export async function createDeposit(amount: number, method: string) {
  const { data, error } = await supabase.rpc('create_deposit', {
    p_amount: amount,
    p_method: method,
  });
  if (error) throw error;
  return data;
}

export async function listMyDeposits(): Promise<Deposit[]> {
  const { data, error } = await supabase
    .from('deposits')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as Deposit[];
}

/* ---------- Withdrawals ---------- */

export async function requestWithdrawal(amount: number, method: string, destination: string) {
  const { data, error } = await supabase.rpc('request_withdrawal', {
    p_amount: amount,
    p_method: method,
    p_destination: destination,
  });
  if (error) throw error;
  return data;
}

export async function listMyWithdrawals(): Promise<Withdrawal[]> {
  const { data, error } = await supabase
    .from('withdrawals')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as Withdrawal[];
}

/* ---------- Referrals ---------- */

export async function listMyReferrals(): Promise<ReferralRow[]> {
  const { data, error } = await supabase.rpc('list_my_referrals');
  if (error) throw error;
  return data as ReferralRow[];
}

/* ---------- Support ---------- */

export async function listMyTickets(): Promise<SupportTicket[]> {
  const { data, error } = await supabase
    .from('support_tickets')
    .select('*')
    .order('updated_at', { ascending: false });
  if (error) throw error;
  return data as SupportTicket[];
}

export async function createTicket(input: { subject: string; message: string; category: string; priority: string }) {
  const { data, error } = await supabase
    .from('support_tickets')
    .insert({
      subject: input.subject,
      message: input.message,
      category: input.category,
      priority: input.priority,
    })
    .select()
    .maybeSingle();
  if (error) throw error;
  return data as SupportTicket;
}

export async function getTicketReplies(ticketId: string): Promise<TicketReply[]> {
  const { data, error } = await supabase
    .from('ticket_replies')
    .select('*')
    .eq('ticket_id', ticketId)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return data as TicketReply[];
}

export async function replyToTicket(ticketId: string, message: string) {
  const { data, error } = await supabase
    .from('ticket_replies')
    .insert({ ticket_id: ticketId, message, is_staff: false })
    .select()
    .maybeSingle();
  if (error) throw error;
  await supabase.from('support_tickets').update({ status: 'open' }).eq('id', ticketId);
  return data as TicketReply;
}

export async function closeTicket(ticketId: string) {
  const { error } = await supabase
    .from('support_tickets')
    .update({ status: 'closed' })
    .eq('id', ticketId);
  if (error) throw error;
}

/* ---------- Settings ---------- */

export async function getSettings(): Promise<AppSettings> {
  const { data, error } = await supabase
    .from('app_settings')
    .select('*')
    .eq('id', 1)
    .maybeSingle();
  if (error) throw error;
  return data as AppSettings;
}

/* ---------- Admin ---------- */

export async function adminGetStats(): Promise<AdminStats> {
  const { data, error } = await supabase.rpc('admin_stats');
  if (error) throw error;
  return data as AdminStats;
}

export async function adminListUsers(search?: string): Promise<AdminUserRow[]> {
  const { data, error } = await supabase.rpc('admin_list_users', {
    p_search: search ?? null,
    p_limit: 100,
    p_offset: 0,
  });
  if (error) throw error;
  return data as AdminUserRow[];
}

export async function adminGetUserDetail(userId: string) {
  const { data, error } = await supabase.rpc('admin_get_user_detail', { p_user_id: userId });
  if (error) throw error;
  return data;
}

export async function adminSetUserStatus(userId: string, status: string) {
  const { data, error } = await supabase.rpc('admin_set_user_status', {
    p_user_id: userId,
    p_status: status,
  });
  if (error) throw error;
  return data;
}

export async function adminListDeposits(status?: string): Promise<AdminDepositRow[]> {
  const { data, error } = await supabase.rpc('admin_list_deposits', {
    p_status: status ?? null,
    p_limit: 100,
    p_offset: 0,
  });
  if (error) throw error;
  return data as AdminDepositRow[];
}

export async function adminApproveDeposit(depositId: string) {
  const { data, error } = await supabase.rpc('approve_deposit', { p_deposit_id: depositId });
  if (error) throw error;
  return data;
}

export async function adminRejectDeposit(depositId: string, note: string) {
  const { data, error } = await supabase.rpc('reject_deposit', {
    p_deposit_id: depositId,
    p_note: note,
  });
  if (error) throw error;
  return data;
}

export async function adminListWithdrawals(status?: string): Promise<AdminWithdrawalRow[]> {
  const { data, error } = await supabase.rpc('admin_list_withdrawals', {
    p_status: status ?? null,
    p_limit: 100,
    p_offset: 0,
  });
  if (error) throw error;
  return data as AdminWithdrawalRow[];
}

export async function adminApproveWithdrawal(withdrawalId: string) {
  const { data, error } = await supabase.rpc('approve_withdrawal', { p_withdrawal_id: withdrawalId });
  if (error) throw error;
  return data;
}

export async function adminRejectWithdrawal(withdrawalId: string, note: string) {
  const { data, error } = await supabase.rpc('reject_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_note: note,
  });
  if (error) throw error;
  return data;
}

export async function adminListTransactions(type?: string, userId?: string, currency?: string): Promise<AdminTransactionRow[]> {
  const { data, error } = await supabase.rpc('admin_list_transactions', {
    p_limit: 200, p_offset: 0, p_type: type ?? null, p_user_id: userId ?? null, p_currency: currency ?? null,
  });
  if (error) throw error;
  return data as AdminTransactionRow[];
}

export async function adminListReferrals(): Promise<AdminReferralRow[]> {
  const { data, error } = await supabase.rpc('admin_list_referrals', { p_limit: 200, p_offset: 0 });
  if (error) throw error;
  return data as AdminReferralRow[];
}

export async function adminListTickets(status?: string): Promise<AdminTicketRow[]> {
  const { data, error } = await supabase.rpc('admin_list_tickets', {
    p_status: status ?? null,
    p_limit: 100,
    p_offset: 0,
  });
  if (error) throw error;
  return data as AdminTicketRow[];
}

export async function adminReplyTicket(ticketId: string, message: string) {
  const { data, error } = await supabase.rpc('admin_reply_ticket', {
    p_ticket_id: ticketId,
    p_message: message,
  });
  if (error) throw error;
  return data;
}

export async function adminSetTicketStatus(ticketId: string, status: string) {
  const { data, error } = await supabase.rpc('admin_ticket_set_status', {
    p_ticket_id: ticketId,
    p_status: status,
  });
  if (error) throw error;
  return data;
}

export async function adminListAuditLogs(): Promise<AuditLog[]> {
  const { data, error } = await supabase.rpc('admin_list_audit_logs', { p_limit: 200, p_offset: 0 });
  if (error) throw error;
  return data as AuditLog[];
}

export async function adminUpdateSettings(input: {
  referral_commission_percent: number;
  referral_deposit_commission_percent: number;
  min_withdrawal: number;
  max_withdrawal: number;
  withdrawal_cooldown_minutes: number;
  ptc_daily_limit_per_ad: number;
  task_daily_limit: number;
  platform_name: string;
  xc_token_name: string;
  xc_token_symbol: string;
  xc_per_usd: number;
  xc_conversion_enabled: boolean;
  xc_min_conversion: number;
  xc_max_conversion: number;
  reward_multiplier: number;
  xc_value_usd: number;
}) {
  const { data, error } = await supabase.rpc('admin_update_settings', {
    p_referral_commission_percent: input.referral_commission_percent,
    p_referral_deposit_commission_percent: input.referral_deposit_commission_percent,
    p_min_withdrawal: input.min_withdrawal,
    p_max_withdrawal: input.max_withdrawal,
    p_withdrawal_cooldown_minutes: input.withdrawal_cooldown_minutes,
    p_ptc_daily_limit_per_ad: input.ptc_daily_limit_per_ad,
    p_task_daily_limit: input.task_daily_limit,
    p_platform_name: input.platform_name,
    p_xc_token_name: input.xc_token_name,
    p_xc_token_symbol: input.xc_token_symbol,
    p_xc_per_usd: input.xc_per_usd,
    p_xc_conversion_enabled: input.xc_conversion_enabled,
    p_xc_min_conversion: input.xc_min_conversion,
    p_xc_max_conversion: input.xc_max_conversion,
    p_reward_multiplier: input.reward_multiplier,
    p_xc_value_usd: input.xc_value_usd,
  });
  if (error) throw error;
  return data;
}

export async function adminReviewTask(completionId: string, approve: boolean, note = '') {
  const { data, error } = await supabase.rpc('admin_review_task', {
    p_completion_id: completionId,
    p_approve: approve,
    p_note: note,
  });
  if (error) throw error;
  return data;
}

export async function adminListPendingTasks(): Promise<TaskCompletion[]> {
  const { data, error } = await supabase
    .from('task_completions')
    .select('*, tasks(title, task_type, reward)')
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) throw error;
  return data as unknown as TaskCompletion[];
}

export async function adminCreatePtcAd(input: {
  title: string; description: string; advertiser: string; category: string;
  reward: number; duration_seconds: number; destination_url: string; image_url: string;
  daily_view_limit: number; total_view_limit: number; active: boolean;
}) {
  const { data, error } = await supabase.rpc('admin_create_ptc_ad', {
    p_title: input.title, p_description: input.description, p_advertiser: input.advertiser,
    p_category: input.category, p_reward: input.reward, p_duration_seconds: input.duration_seconds,
    p_destination_url: input.destination_url, p_image_url: input.image_url,
    p_daily_view_limit: input.daily_view_limit, p_total_view_limit: input.total_view_limit,
    p_active: input.active, p_start_date: null, p_end_date: null,
  });
  if (error) throw error;
  return data;
}

export async function adminUpdatePtcAd(id: string, input: {
  title: string; description: string; advertiser: string; category: string;
  reward: number; duration_seconds: number; destination_url: string; image_url: string;
  daily_view_limit: number; total_view_limit: number; active: boolean;
}) {
  const { data, error } = await supabase.rpc('admin_update_ptc_ad', {
    p_id: id, p_title: input.title, p_description: input.description, p_advertiser: input.advertiser,
    p_category: input.category, p_reward: input.reward, p_duration_seconds: input.duration_seconds,
    p_destination_url: input.destination_url, p_image_url: input.image_url,
    p_daily_view_limit: input.daily_view_limit, p_total_view_limit: input.total_view_limit,
    p_active: input.active, p_start_date: null, p_end_date: null,
  });
  if (error) throw error;
  return data;
}

export async function adminDeletePtcAd(id: string) {
  const { data, error } = await supabase.rpc('admin_delete_ptc_ad', { p_id: id });
  if (error) throw error;
  return data;
}

export async function adminCreateTask(input: {
  title: string; description: string; instructions: string; category: string; task_type: string;
  reward: number; action_url: string; proof_required: boolean; proof_instructions: string;
  daily_limit: number; total_limit: number; active: boolean;
}) {
  const { data, error } = await supabase.rpc('admin_create_task', {
    p_title: input.title, p_description: input.description, p_instructions: input.instructions,
    p_category: input.category, p_task_type: input.task_type, p_reward: input.reward,
    p_action_url: input.action_url, p_proof_required: input.proof_required,
    p_proof_instructions: input.proof_instructions, p_daily_limit: input.daily_limit,
    p_total_limit: input.total_limit, p_active: input.active, p_start_date: null, p_end_date: null,
  });
  if (error) throw error;
  return data;
}

export async function adminUpdateTask(id: string, input: {
  title: string; description: string; instructions: string; category: string; task_type: string;
  reward: number; action_url: string; proof_required: boolean; proof_instructions: string;
  daily_limit: number; total_limit: number; active: boolean;
}) {
  const { data, error } = await supabase.rpc('admin_update_task', {
    p_id: id, p_title: input.title, p_description: input.description, p_instructions: input.instructions,
    p_category: input.category, p_task_type: input.task_type, p_reward: input.reward,
    p_action_url: input.action_url, p_proof_required: input.proof_required,
    p_proof_instructions: input.proof_instructions, p_daily_limit: input.daily_limit,
    p_total_limit: input.total_limit, p_active: input.active, p_start_date: null, p_end_date: null,
  });
  if (error) throw error;
  return data;
}

export async function adminDeleteTask(id: string) {
  const { data, error } = await supabase.rpc('admin_delete_task', { p_id: id });
  if (error) throw error;
  return data;
}

/* ---------- Advertiser ---------- */

export async function adTransferToAdvertising(amount: number) {
  const { data, error } = await supabase.rpc('ad_transfer_to_advertising', { p_amount: amount });
  if (error) throw error;
  return data as { ok: boolean; advertising_balance: number };
}

export async function adGetDashboard(): Promise<AdDashboardData> {
  const { data, error } = await supabase.rpc('ad_get_dashboard');
  if (error) throw error;
  return data as AdDashboardData;
}

export async function adListCampaigns(): Promise<AdCampaignsResult> {
  const { data, error } = await supabase.rpc('ad_list_campaigns');
  if (error) throw error;
  return data as AdCampaignsResult;
}

export async function adCreatePtcCampaign(input: {
  title: string; description: string; advertiser: string; category: string;
  reward: number; duration_seconds: number; destination_url: string; image_url: string;
  daily_view_limit: number; total_view_limit: number; budget: number;
  target_countries?: string[] | null;
  target_devices?: string[];
}) {
  const { data, error } = await supabase.rpc('ad_create_ptc_campaign', {
    p_title: input.title, p_description: input.description, p_advertiser: input.advertiser,
    p_category: input.category, p_reward: input.reward, p_duration_seconds: input.duration_seconds,
    p_destination_url: input.destination_url, p_image_url: input.image_url,
    p_daily_view_limit: input.daily_view_limit, p_total_view_limit: input.total_view_limit,
    p_budget: input.budget,
    p_target_countries: input.target_countries ?? null,
    p_target_devices: input.target_devices ?? ['desktop', 'mobile', 'tablet'],
  });
  if (error) throw error;
  return data;
}

export async function adCreateTaskCampaign(input: {
  title: string; description: string; instructions: string; category: string;
  task_type: string; reward: number; action_url: string;
  proof_required: boolean; proof_instructions: string;
  daily_limit: number; total_limit: number; budget: number;
  target_countries: string[] | null;
  proof_image_url: string | null;
}) {
  const { data, error } = await supabase.rpc('ad_create_task_campaign', {
    p_title: input.title, p_description: input.description, p_instructions: input.instructions,
    p_category: input.category, p_task_type: input.task_type, p_reward: input.reward,
    p_action_url: input.action_url, p_proof_required: input.proof_required,
    p_proof_instructions: input.proof_instructions, p_daily_limit: input.daily_limit,
    p_total_limit: input.total_limit, p_budget: input.budget,
    p_target_countries: input.target_countries,
    p_proof_image_url: input.proof_image_url,
  });
  if (error) throw error;
  return data;
}

export async function adPauseCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('ad_pause_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

export async function adResumeCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('ad_resume_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

export async function adStopCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('ad_stop_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

/* ---------- Admin: Campaign Approval ---------- */

export async function adminListPendingCampaigns(): Promise<AdminPendingCampaignsResult> {
  const { data, error } = await supabase.rpc('admin_list_pending_campaigns');
  if (error) throw error;
  return data as AdminPendingCampaignsResult;
}

export async function adminApproveCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('admin_approve_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

export async function adminRejectCampaign(campaignId: string, type: 'ptc' | 'task', note: string) {
  const { data, error } = await supabase.rpc('admin_reject_campaign', {
    p_campaign_id: campaignId, p_type: type, p_note: note,
  });
  if (error) throw error;
  return data;
}

/* ---------- Admin: User Management ---------- */

export async function adminSetUserRole(userId: string, role: string) {
  const { data, error } = await supabase.rpc('admin_set_user_role', {
    p_user_id: userId, p_role: role,
  });
  if (error) throw error;
  return data;
}

export interface AdminAdjustBalanceResult {
  ok: boolean;
  currency: string;
  action: string;
  amount: number;
  before: number;
  after: number;
  transaction_id: string;
  reference: string;
  reason: string;
}

export async function adminAdjustUserBalance(
  userId: string,
  currency: 'USDT' | 'XC',
  action: 'ADD' | 'SUBTRACT',
  amount: number,
  reason: string
): Promise<AdminAdjustBalanceResult> {
  const { data, error } = await supabase.rpc('admin_adjust_user_balance', {
    p_user_id: userId,
    p_currency: currency,
    p_action: action,
    p_amount: amount,
    p_reason: reason,
  });
  if (error) throw error;
  return data as AdminAdjustBalanceResult;
}

/* ---------- Admin: Impersonation ---------- */

export async function detectUserCountry(): Promise<{ country: string | null; detected: boolean }> {
  const { data, error } = await supabase.functions.invoke('detect-user-country');
  if (error) return { country: null, detected: false };
  return data;
}

export async function adminUpdateUserCountry(userId: string, country: string): Promise<{ ok: boolean }> {
  const { data, error } = await supabase.rpc('admin_update_user_country', {
    p_user_id: userId,
    p_country: country,
  });
  if (error) throw error;
  return data as { ok: boolean };
}

export async function adminListUndetectedUsers(): Promise<Array<{ id: string; username: string; email: string | null; created_at: string }>> {
  const { data, error } = await supabase.rpc('admin_list_undetected_users');
  if (error) throw error;
  return (data as Array<{ id: string; username: string; email: string | null; created_at: string }>) ?? [];
}

export async function adminBulkSetCountry(userIds: string[], country: string): Promise<{ ok: boolean; updated_count: number }> {
  const { data, error } = await supabase.rpc('admin_bulk_set_country', {
    p_user_ids: userIds,
    p_country: country,
  });
  if (error) throw error;
  return data as { ok: boolean; updated_count: number };
}

export async function adminImpersonateUser(targetUserId: string): Promise<{
  access_token: string;
  refresh_token: string;
  user_id: string;
  username: string;
}> {
  const { data, error } = await supabase.functions.invoke('admin-impersonate', {
    body: { targetUserId },
  });
  if (error) {
    let message = 'Failed to impersonate user';
    try {
      const context = (error as any).context;
      if (context) {
        const body = await context.json();
        if (body?.error) message = body.error;
      }
    } catch {
      // fall back to default message
    }
    throw new Error(message);
  }
  if (data?.error) throw new Error(data.error);
  return data;
}

/* ---------- Admin: Advertiser & Campaign Management ---------- */

export async function adminListAdvertisers(): Promise<AdminAdvertiserRow[]> {
  const { data, error } = await supabase.rpc('admin_list_advertisers');
  if (error) throw error;
  return data as AdminAdvertiserRow[];
}

export async function adminListAllCampaigns(type?: string, status?: string): Promise<AdminAllCampaignsResult> {
  const { data, error } = await supabase.rpc('admin_list_all_campaigns', {
    p_type: type ?? null, p_status: status ?? null,
  });
  if (error) throw error;
  return data as AdminAllCampaignsResult;
}

export async function adminPauseCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('admin_pause_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

export async function adminResumeCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('admin_resume_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

export async function adminStopCampaign(campaignId: string, type: 'ptc' | 'task') {
  const { data, error } = await supabase.rpc('admin_stop_campaign', {
    p_campaign_id: campaignId, p_type: type,
  });
  if (error) throw error;
  return data;
}

/* ===========================================================
 * Offer System API
 * =========================================================== */

export async function offerListAvailable(
  offerType: 'all' | 'survey' | 'app_install' | 'game' = 'all',
  platform: 'all' | 'android' | 'ios' | 'web' = 'all',
): Promise<Offer[]> {
  const { data, error } = await supabase.rpc('offer_list_available', {
    p_offer_type: offerType,
    p_platform: platform,
  });
  if (error) throw error;
  return (data as Offer[]) ?? [];
}

export async function offerStartSession(offerId: string): Promise<OfferStartResult> {
  const { data, error } = await supabase.rpc('offer_start_session', {
    p_offer_id: offerId,
  });
  if (error) throw error;
  return data as OfferStartResult;
}

export async function offerListMySessions(
  status: 'all' | 'pending' | 'completed' | 'reversed' = 'all',
  limit = 50,
  offset = 0,
): Promise<OfferSession[]> {
  const { data, error } = await supabase.rpc('offer_list_my_sessions', {
    p_status: status,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;
  return (data as OfferSession[]) ?? [];
}

export async function offerGetSession(sessionId: string): Promise<OfferSessionDetail | null> {
  const { data, error } = await supabase.rpc('offer_get_session', {
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data as OfferSessionDetail | null;
}

/* ---------- Admin Offer API ---------- */

export async function offerAdminStats(): Promise<OfferAdminStats> {
  const { data, error } = await supabase.rpc('offer_admin_stats');
  if (error) throw error;
  return data as OfferAdminStats;
}

export async function offerAdminListSessions(params: {
  providerSlug?: string | null;
  offerType?: string | null;
  status?: string | null;
  userId?: string | null;
  limit?: number;
  offset?: number;
} = {}): Promise<OfferAdminSession[]> {
  const { data, error } = await supabase.rpc('offer_admin_list_sessions', {
    p_provider_slug: params.providerSlug ?? null,
    p_offer_type: params.offerType ?? null,
    p_status: params.status ?? null,
    p_user_id: params.userId ?? null,
    p_limit: params.limit ?? 100,
    p_offset: params.offset ?? 0,
  });
  if (error) throw error;
  return (data as OfferAdminSession[]) ?? [];
}

export async function offerAdminListProviders(): Promise<OfferProviderAdmin[]> {
  const { data, error } = await supabase.rpc('offer_admin_list_providers');
  if (error) throw error;
  return (data as OfferProviderAdmin[]) ?? [];
}

export async function offerAdminUpdateProvider(params: {
  providerId: string;
  enabled?: boolean | null;
  displayName?: string | null;
  publisherId?: string | null;
  rewardMarginPercent?: number | null;
  config?: Record<string, unknown> | null;
}): Promise<{ ok: boolean; error?: string }> {
  const { data, error } = await supabase.rpc('offer_admin_update_provider', {
    p_provider_id: params.providerId,
    p_enabled: params.enabled ?? null,
    p_display_name: params.displayName ?? null,
    p_publisher_id: params.publisherId ?? null,
    p_reward_margin_percent: params.rewardMarginPercent ?? null,
    p_config: params.config ?? null,
  });
  if (error) throw error;
  return data as { ok: boolean; error?: string };
}

export async function offerAdminCreateProvider(params: {
  slug: string;
  displayName: string;
  providerType: string;
  publisherId?: string;
  postbackUrl?: string;
  rewardMarginPercent?: number;
  config?: Record<string, unknown>;
}): Promise<{ ok: boolean; id?: string; error?: string }> {
  const { data, error } = await supabase.rpc('offer_admin_create_provider', {
    p_slug: params.slug,
    p_display_name: params.displayName,
    p_provider_type: params.providerType,
    p_publisher_id: params.publisherId ?? '',
    p_postback_url: params.postbackUrl ?? '',
    p_reward_margin_percent: params.rewardMarginPercent ?? 100,
    p_config: params.config ?? {},
  });
  if (error) throw error;
  return data as { ok: boolean; id?: string; error?: string };
}

export async function offerAdminSetProviderSecret(params: {
  providerId: string;
  secretType: 'api_key' | 'postback_secret';
  secretValue: string;
}): Promise<{ ok: boolean; error?: string }> {
  const { data, error } = await supabase.rpc('offer_admin_set_provider_secret', {
    p_provider_id: params.providerId,
    p_secret_type: params.secretType,
    p_secret_value: params.secretValue,
  });
  if (error) throw error;
  return data as { ok: boolean; error?: string };
}

export async function offerAdminTriggerSync(providerSlug?: string | null) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Not authenticated');
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/offer-sync`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ provider_slug: providerSlug ?? null }),
  });
  const result = await response.json().catch(() => ({ error: 'Failed to sync offers' }));
  if (!response.ok) throw new Error(result.error || 'Failed to sync offers');
  return result as {
    ok: boolean; synced?: number;
    results?: Array<{ slug: string; synced: number; error: string | null }>;
    message?: string; error?: string;
  };
}

/* ---------- Campaign Image Upload ---------- */

export async function uploadCampaignImage(file: File): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Not authenticated');
  const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg';
  const path = `${session.user.id}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage
    .from('campaign-images')
    .upload(path, file, { cacheControl: '3600', upsert: false });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('campaign-images').getPublicUrl(path);
  return pub.publicUrl;
}
