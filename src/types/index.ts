export type UserRole = 'user' | 'moderator' | 'admin';
export type UserStatus = 'active' | 'suspended' | 'banned';

export interface Profile {
  id: string;
  username: string;
  full_name: string;
  email: string;
  country: string;
  role: UserRole;
  status: UserStatus;
  referral_code: string;
  referred_by: string | null;
  avatar_url: string;
  available_balance: number;
  pending_balance: number;
  advertising_balance: number;
  xc_balance: number;
  total_earned: number;
  total_withdrawn: number;
  total_deposited: number;
  ptc_views: number;
  tasks_completed: number;
  created_at: string;
  updated_at: string;
}

export type TransactionType =
  | 'ptc_reward'
  | 'task_reward'
  | 'referral_reward'
  | 'deposit'
  | 'withdrawal'
  | 'withdrawal_refund'
  | 'adjustment'
  | 'ad_transfer'
  | 'ad_spend'
  | 'ad_refund'
  | 'offer_reward'
  | 'offer_reversal'
  | 'xc_conversion'
  | 'xc_transfer_sent'
  | 'xc_transfer_received';

export type TransactionCurrency = 'USD' | 'XC';

export type TransactionStatus = 'pending' | 'completed' | 'failed' | 'reversed';

export interface Transaction {
  id: string;
  user_id: string;
  type: TransactionType;
  amount: number;
  currency: TransactionCurrency;
  usd_equivalent: number | null;
  base_usd_amount: number | null;
  reward_multiplier: number | null;
  reference_type: string | null;
  reference_id: string | null;
  reference: string | null;
  description: string;
  status: TransactionStatus;
  created_at: string;
}

export interface PtcAd {
  id: string;
  title: string;
  description: string;
  advertiser: string;
  category: string;
  reward: number;
  duration_seconds: number;
  destination_url: string;
  image_url: string;
  daily_view_limit: number;
  total_view_limit: number;
  total_views: number;
  active: boolean;
  start_date: string | null;
  end_date: string | null;
  created_at: string;
}

export type PtcViewStatus = 'pending' | 'completed' | 'expired' | 'cancelled';

export interface PtcAdView {
  id: string;
  user_id: string;
  ptc_ad_id: string;
  started_at: string;
  completed_at: string | null;
  required_duration: number;
  reward: number;
  status: PtcViewStatus;
  view_date: string;
}

export type TaskType =
  | 'visit_website'
  | 'registration'
  | 'social_follow'
  | 'app_install'
  | 'survey'
  | 'submit_proof'
  | 'custom';

export interface Task {
  id: string;
  title: string;
  description: string;
  instructions: string;
  category: string;
  task_type: TaskType;
  reward: number;
  action_url: string;
  proof_required: boolean;
  proof_instructions: string;
  daily_limit: number;
  total_limit: number;
  total_completions: number;
  active: boolean;
  start_date: string | null;
  end_date: string | null;
  target_all_countries: boolean;
  target_countries: string[];
  created_at: string;
}

export type TaskCompletionStatus = 'pending' | 'approved' | 'rejected';

export interface TaskCompletion {
  id: string;
  user_id: string;
  task_id: string;
  proof_text: string;
  reward: number;
  status: TaskCompletionStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
}

export type DepositStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';

export interface Deposit {
  id: string;
  user_id: string;
  amount: number;
  payment_method: string;
  status: DepositStatus;
  admin_note: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
}

export type WithdrawalStatus = 'pending' | 'paid' | 'rejected' | 'cancelled';

export interface Withdrawal {
  id: string;
  user_id: string;
  amount: number;
  withdrawal_method: string;
  destination: string;
  status: WithdrawalStatus;
  admin_note: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
}

export interface Referral {
  id: string;
  referrer_id: string;
  referred_id: string;
  qualified: boolean;
  reward_amount: number;
  created_at: string;
  qualified_at: string | null;
  referred_username: string | null;
  referred_email: string | null;
}

export interface ReferralRow {
  id: string;
  username: string;
  email: string;
  created_at: string;
  reward_amount: number;
}

export type TicketStatus = 'open' | 'pending' | 'closed';
export type TicketPriority = 'low' | 'normal' | 'high' | 'urgent';

export interface SupportTicket {
  id: string;
  user_id: string;
  subject: string;
  message: string;
  category: string;
  priority: TicketPriority;
  status: TicketStatus;
  created_at: string;
  updated_at: string;
}

export interface TicketReply {
  id: string;
  ticket_id: string;
  user_id: string;
  message: string;
  is_staff: boolean;
  created_at: string;
}

export interface AppSettings {
  id: number;
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
}

export interface DashboardData {
  available_balance: number;
  pending_balance: number;
  xc_balance: number;
  total_earned: number;
  xc_total_earned: number;
  total_withdrawn: number;
  total_deposited: number;
  today_earned: number;
  xc_today_earned: number;
  xc_total_sent: number;
  referral_earned: number;
  ptc_views: number;
  tasks_completed: number;
  pending_withdrawals: number;
  role: UserRole;
  status: UserStatus;
  earnings_series: { date: string; amount: number }[];
}

export interface PtcStartResult {
  view_id: string;
  started_at: string;
  required_duration: number;
  reward: number;
  status: PtcViewStatus;
  session_token: string;
}

export interface PtcHeartbeatResult {
  ok: boolean;
  active_seconds: number;
  required_duration: number;
  remaining: number;
}

export interface PtcClaimResult {
  ok: boolean;
  reward?: number;
  usd_equivalent?: number;
  transaction_id?: string;
  completed_at?: string;
  already_claimed?: boolean;
}

export interface AdminUserRow {
  id: string;
  username: string;
  email: string;
  full_name: string;
  country: string;
  role: UserRole;
  status: UserStatus;
  available_balance: number;
  advertising_balance: number;
  xc_balance: number;
  total_earned: number;
  total_withdrawn: number;
  total_deposited: number;
  ptc_views: number;
  tasks_completed: number;
  created_at: string;
  referrer_username: string | null;
}

export interface AdminDepositRow extends Deposit {
  username: string;
  email: string;
}

export interface AdminWithdrawalRow extends Withdrawal {
  username: string;
  email: string;
}

export interface AdminTransactionRow extends Transaction {
  username: string;
  currency: TransactionCurrency;
  usd_equivalent: number | null;
  base_usd_amount: number | null;
  reward_multiplier: number | null;
}

export interface AdminReferralRow extends Referral {
  referrer: string;
  referred: string;
}

export interface AdminTicketRow extends SupportTicket {
  username: string;
}

export interface XcRecipientLookup {
  found: boolean;
  id?: string;
  username?: string;
  full_name?: string | null;
  avatar_url?: string | null;
}

export interface XcTransferResult {
  ok: boolean;
  duplicate?: boolean;
  transfer_id: string;
  reference: string;
  amount: number;
  recipient_username: string;
  sender_xc_balance: number;
  recipient_xc_balance?: number;
}

export interface XcTransferHistoryRow {
  id: string;
  reference: string;
  amount: number;
  status: string;
  created_at: string;
  completed_at: string | null;
  direction: 'sent' | 'received';
  sender_username: string;
  recipient_username: string;
}

export interface AdminXcTransferRow {
  id: string;
  reference: string;
  amount: number;
  status: string;
  created_at: string;
  completed_at: string | null;
  sender_id: string;
  sender_username: string;
  recipient_id: string;
  recipient_username: string;
}

export interface AuditLog {
  id: string;
  actor_id: string | null;
  actor_username: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  details: Record<string, unknown> | null;
  created_at: string;
}

export type CampaignStatus = 'draft' | 'pending' | 'active' | 'paused' | 'completed' | 'rejected';

export interface AdPtcCampaign {
  id: string;
  title: string;
  category: string;
  reward: number;
  duration_seconds: number;
  budget: number;
  spent: number;
  status: CampaignStatus;
  active: boolean;
  total_views: number;
  daily_view_limit: number;
  total_view_limit: number;
  target_all_countries: boolean;
  target_devices: string[];
  target_countries: string[];
  created_at: string;
}

export interface AdTaskCampaign {
  id: string;
  title: string;
  category: string;
  reward: number;
  task_type: TaskType;
  budget: number;
  spent: number;
  status: CampaignStatus;
  active: boolean;
  total_completions: number;
  daily_limit: number;
  total_limit: number;
  target_all_countries: boolean;
  target_countries: string[];
  created_at: string;
}

export interface AdDashboardData {
  advertising_balance: number;
  ptc_campaigns: number;
  ptc_active: number;
  task_campaigns: number;
  task_active: number;
  total_budget: number;
  total_spent: number;
  ptc_views: number;
  task_completions: number;
}

export interface AdCampaignsResult {
  ptc_campaigns: AdPtcCampaign[] | null;
  task_campaigns: AdTaskCampaign[] | null;
}

export interface AdminPendingCampaign {
  id: string;
  title: string;
  category: string;
  reward: number;
  budget: number;
  advertiser_id: string;
  advertiser_name: string;
  target_all_countries: boolean;
  target_devices: string[];
  target_countries: string[];
  created_at: string;
}

export interface AdminPendingCampaignsResult {
  ptc_campaigns: AdminPendingCampaign[] | null;
  task_campaigns: (AdminPendingCampaign & {
    task_type: TaskType;
    action_url: string;
    proof_required: boolean;
    proof_instructions: string;
    daily_limit: number;
    total_limit: number;
  })[] | null;
}

export interface AdminStats {
  pending_campaigns: number;
  total_ad_spend: number;
  active_advertisers: number;
  users: number;
  active_ads: number;
  active_tasks: number;
  total_ptc_views: number;
  total_task_completions: number;
  pending_deposits: number;
  pending_withdrawals: number;
  total_deposited: number;
  total_withdrawn: number;
  total_paid_out: number;
  total_balance: number;
  total_ad_balance: number;
  ptc_campaigns: number;
  task_campaigns: number;
  active_campaigns: number;
  completed_campaigns: number;
  xc_total_issued: number;
  xc_ptc_earned: number;
  xc_offer_earned: number;
  xc_task_earned: number;
  xc_total_balance: number;
  reward_multiplier: number;
  xc_value_usd: number;
}

export interface AdminAdvertiserRow {
  id: string;
  username: string;
  email: string;
  advertising_balance: number;
  status: UserStatus;
  created_at: string;
  ptc_campaigns: number;
  task_campaigns: number;
  total_spent: number;
  active_campaigns: number;
  pending_campaigns: number;
}

export interface AdminAllCampaign {
  id: string;
  title: string;
  category: string;
  reward: number;
  budget: number;
  spent: number;
  status: CampaignStatus;
  active: boolean;
  advertiser_id: string;
  advertiser_name: string;
  created_at: string;
}

export interface AdminAllPtcCampaign extends AdminAllCampaign {
  duration_seconds: number;
  total_views: number;
  destination_url: string;
  daily_view_limit: number;
  total_view_limit: number;
  target_all_countries: boolean;
  target_devices: string[];
  target_countries: string[];
}

export interface AdminAllTaskCampaign extends AdminAllCampaign {
  task_type: TaskType;
  total_completions: number;
  action_url: string;
  proof_required: boolean;
  daily_limit: number;
  total_limit: number;
  target_all_countries: boolean;
  target_countries: string[];
}

export interface AdminAllCampaignsResult {
  ptc_campaigns: AdminAllPtcCampaign[] | null;
  task_campaigns: AdminAllTaskCampaign[] | null;
}

/* ---------- Offer System Types ---------- */

export type OfferType = 'survey' | 'app_install' | 'game' | 'signup' | 'trial' | 'other';
export type OfferPlatform = 'android' | 'ios' | 'web' | 'all';
export type OfferDifficulty = 'easy' | 'medium' | 'hard';
export type OfferSessionStatus =
  | 'clicked' | 'started' | 'pending'
  | 'completed' | 'rejected' | 'reversed' | 'expired';

export interface Offer {
  id: string;
  provider_id: string;
  provider_slug: string;
  provider_name: string;
  provider_offer_id: string;
  title: string;
  description: string;
  requirements: string;
  offer_type: OfferType;
  reward: number;
  currency_code: string;
  icon_url: string;
  destination_url: string;
  platform: OfferPlatform;
  estimated_time_minutes: number;
  difficulty: OfferDifficulty;
  category: string;
}

export interface OfferStartResult {
  session_id: string;
  tracking_id: string;
  tracking_url: string;
  reward: number;
  currency: string;
  offer_type: string;
  title: string;
  error?: string;
}

export interface OfferSession {
  id: string;
  tracking_id: string;
  provider_slug: string;
  provider_offer_id: string;
  offer_type: OfferType;
  status: OfferSessionStatus;
  reward: number;
  currency_code: string;
  provider_conversion_id: string | null;
  created_at: string;
  completed_at: string | null;
  reversed_at: string | null;
  offer_title: string | null;
  offer_icon: string | null;
}

export interface OfferSessionDetail extends OfferSession {
  metadata: Record<string, unknown>;
  offer_description: string | null;
  offer_requirements: string | null;
  offer_platform: OfferPlatform | null;
  estimated_time_minutes: number | null;
  difficulty: OfferDifficulty | null;
}

export interface OfferAdminStats {
  total_clicks: number;
  started: number;
  completed: number;
  pending: number;
  reversed: number;
  rejected: number;
  total_rewards: number;
  total_revenue: number;
  active_providers: number;
  total_providers: number;
  total_offers: number;
}

export interface OfferAdminSession {
  id: string;
  user_id: string;
  username: string;
  email: string;
  provider_slug: string;
  provider_offer_id: string;
  offer_type: OfferType;
  status: OfferSessionStatus;
  reward: number;
  revenue: number;
  provider_conversion_id: string | null;
  tracking_id: string;
  created_at: string;
  completed_at: string | null;
  reversed_at: string | null;
  offer_title: string | null;
}

export interface OfferProviderAdmin {
  id: string;
  slug: string;
  display_name: string;
  provider_type: string;
  enabled: boolean;
  has_api_key: boolean;
  has_postback_secret: boolean;
  publisher_id: string;
  postback_url: string;
  currency_code: string;
  reward_margin_percent: number;
  config: Record<string, unknown>;
  last_synced_at: string | null;
  created_at: string;
}

/* ---------- Public Profile + Follow System ---------- */

export interface PublicProfile {
  found: boolean;
  username?: string;
  bio?: string;
  country?: string;
  avatar_url?: string | null;
  xc_balance?: number;
  created_at?: string;
  last_seen_at?: string | null;
  follower_count?: number;
  following_count?: number;
  is_following?: boolean;
  is_self?: boolean;
}

export interface FollowListRow {
  username: string;
  avatar_url: string | null;
  is_following: boolean;
}

export interface FollowResult {
  ok: boolean;
  follower_count: number;
}
