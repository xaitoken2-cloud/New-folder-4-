import { useEffect, useState } from 'react';
import { adminGetStats, getErrorMessage } from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, StatCard } from '@/components/ui';
import { formatMoney, formatXc } from '@/lib/format';
import { Users, MousePointerClick, ListChecks, ArrowDownToLine, ArrowUpFromLine, DollarSign, TrendingUp, Activity, Megaphone, Coins, Zap } from 'lucide-react';
import type { AdminStats } from '@/types';

export function AdminDashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const s = await adminGetStats();
      setStats(s);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load admin stats'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  if (loading) return <LoadingScreen label="Loading admin dashboard..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Admin Dashboard" subtitle="Platform overview and statistics" />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Total Users" value={stats?.users ?? 0} icon={<Users size={18} />} accent="brand" />
        <StatCard label="Active Ads" value={stats?.active_ads ?? 0} icon={<MousePointerClick size={18} />} accent="green" />
        <StatCard label="Active Tasks" value={stats?.active_tasks ?? 0} icon={<ListChecks size={18} />} accent="brand" />
        <StatCard label="PTC Views" value={stats?.total_ptc_views ?? 0} icon={<Activity size={18} />} accent="neutral" />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Task Completions" value={stats?.total_task_completions ?? 0} icon={<ListChecks size={18} />} accent="green" />
        <StatCard label="Pending Campaigns" value={stats?.pending_campaigns ?? 0} icon={<Megaphone size={18} />} accent="brand" sublabel="Awaiting approval" />
        <StatCard label="Total Ad Spend" value={formatMoney(stats?.total_ad_spend ?? 0)} icon={<TrendingUp size={18} />} accent="blue" />
        <StatCard label="Active Advertisers" value={stats?.active_advertisers ?? 0} icon={<Users size={18} />} accent="green" />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Pending Deposits" value={stats?.pending_deposits ?? 0} icon={<ArrowDownToLine size={18} />} accent="brand" />
        <StatCard label="Pending Withdrawals" value={stats?.pending_withdrawals ?? 0} icon={<ArrowUpFromLine size={18} />} accent="neutral" />
        <StatCard label="Total Paid Out" value={formatMoney(stats?.total_paid_out ?? 0)} icon={<DollarSign size={18} />} accent="brand" />
        <StatCard label="Total Deposited" value={formatMoney(stats?.total_deposited ?? 0)} icon={<ArrowDownToLine size={18} />} accent="green" />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Total Withdrawn" value={formatMoney(stats?.total_withdrawn ?? 0)} icon={<ArrowUpFromLine size={18} />} accent="brand" />
        <StatCard label="Total Balance" value={formatMoney(stats?.total_balance ?? 0)} icon={<DollarSign size={18} />} accent="green" />
        <StatCard label="Ad Balance" value={formatMoney(stats?.total_ad_balance ?? 0)} icon={<TrendingUp size={18} />} accent="brand" />
        <StatCard label="Active Campaigns" value={stats?.active_campaigns ?? 0} icon={<Megaphone size={18} />} accent="neutral" />
      </div>

      <h3 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mt-8 mb-3 flex items-center gap-2">
        <Coins size={16} className="text-brand-400" /> XC Token Economy
      </h3>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="XC Total Issued" value={`${formatXc(stats?.xc_total_issued ?? 0)} XC`} icon={<Coins size={18} />} accent="brand" />
        <StatCard label="XC Total Balance" value={`${formatXc(stats?.xc_total_balance ?? 0)} XC`} icon={<Coins size={18} />} accent="green" />
        <StatCard label="XC from PTC" value={`${formatXc(stats?.xc_ptc_earned ?? 0)} XC`} icon={<MousePointerClick size={18} />} accent="neutral" />
        <StatCard label="XC from Offers" value={`${formatXc(stats?.xc_offer_earned ?? 0)} XC`} icon={<Zap size={18} />} accent="brand" />
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="XC from Tasks" value={`${formatXc(stats?.xc_task_earned ?? 0)} XC`} icon={<ListChecks size={18} />} accent="green" />
        <StatCard label="Reward Multiplier" value={`${stats?.reward_multiplier ?? 1}x`} icon={<Zap size={18} />} accent="brand" />
        <StatCard label="XC Value (USD)" value={formatMoney(stats?.xc_value_usd ?? 0)} icon={<DollarSign size={18} />} accent="neutral" />
        <StatCard label="Completed Campaigns" value={stats?.completed_campaigns ?? 0} icon={<Megaphone size={18} />} accent="brand" />
      </div>

      {(stats?.pending_campaigns ?? 0) > 0 && (
        <div className="card p-4 mt-6 border-brand-500/20 bg-brand-500/5">
          <p className="text-sm text-brand-400 flex items-center gap-2">
            <Megaphone size={16} /> {stats?.pending_campaigns} advertiser campaign(s) awaiting approval.
          </p>
        </div>
      )}
      {(stats?.pending_deposits ?? 0) > 0 && (
        <div className="card p-4 mt-6 border-brand-500/20 bg-brand-500/5">
          <p className="text-sm text-brand-400 flex items-center gap-2">
            <TrendingUp size={16} /> {stats?.pending_deposits} deposit(s) awaiting your review.
          </p>
        </div>
      )}
      {(stats?.pending_withdrawals ?? 0) > 0 && (
        <div className="card p-4 mt-3 border-warning-500/20 bg-warning-500/5">
          <p className="text-sm text-warning-500 flex items-center gap-2">
            <ArrowUpFromLine size={16} /> {stats?.pending_withdrawals} withdrawal(s) awaiting your review.
          </p>
        </div>
      )}
    </div>
  );
}
