import { useEffect, useRef, useState } from 'react';
import { Link } from '@/lib/router';
import { adGetDashboard, getErrorMessage } from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, StatCard } from '@/components/ui';
import { formatMoney } from '@/lib/format';
import {
  MousePointerClick, ListChecks, Wallet,
  DollarSign, ArrowRight, Plus, ArrowDownToLine,
} from 'lucide-react';
import { useAuth } from '@/lib/auth';
import type { AdDashboardData } from '@/types';

export function AdvertiserDashboardPage() {
  const { profile } = useAuth();
  const [dashboard, setDashboard] = useState<AdDashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      setDashboard(await adGetDashboard());
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load dashboard'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const [campaignRowWidth, setCampaignRowWidth] = useState<number | null>(null);
  const campaignRowRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!campaignRowRef.current) return;
    const el = campaignRowRef.current;
    const sync = () => setCampaignRowWidth(el.offsetWidth);
    sync();
    const ro = new ResizeObserver(sync);
    ro.observe(el);
    return () => ro.disconnect();
  }, [loading]);

  if (loading) return <LoadingScreen label="Loading advertiser dashboard..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!dashboard) return null;

  return (
    <div>
      <PageHeader
        title="Advertiser Dashboard"
        subtitle="Your PTC ad and task campaign statistics"
      />

      {/* Balance cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className="card p-6">
          <div className="flex items-center justify-between flex-wrap gap-4">
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wide mb-1">USD Balance</div>
              <div className="text-3xl font-mono font-bold text-gray-100">{formatMoney(profile?.available_balance ?? 0)}</div>
            </div>
            <Link to="/deposits" className="btn-primary">
              <ArrowDownToLine size={18} /> Deposit
            </Link>
          </div>
        </div>
        <div className="card p-6">
          <div className="flex items-center justify-between flex-wrap gap-4">
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wide mb-1">Advertising Balance</div>
              <div className="text-3xl font-mono font-bold text-brand-400">{formatMoney(dashboard.advertising_balance)}</div>
            </div>
            <Link to="/advertiser/fund" className="btn-primary">
              <Wallet size={18} /> Add Funds
            </Link>
          </div>
        </div>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          label="PTC Campaigns"
          value={dashboard.ptc_campaigns}
          icon={<MousePointerClick size={18} />}
          sublabel={`${dashboard.ptc_active} active`}
        />
        <StatCard
          label="Task Campaigns"
          value={dashboard.task_campaigns}
          icon={<ListChecks size={18} />}
          sublabel={`${dashboard.task_active} active`}
        />
        <StatCard
          label="Total Budget"
          value={formatMoney(dashboard.total_budget)}
          icon={<DollarSign size={18} />}
        />
        <StatCard
          label="Total Spent"
          value={formatMoney(dashboard.total_spent)}
          icon={<ArrowRight size={18} />}
        />
      </div>

      {/* Campaign creation buttons */}
      <div className="flex justify-center items-center gap-3 mb-6 mt-[100px]">
        <div ref={campaignRowRef} className="flex items-center gap-3 w-fit">
          <Link to="/advertiser/create-ptc" className="btn-primary text-sm">
            <Plus size={16} /> PTC Campaign
          </Link>
          <Link to="/advertiser/create-task" className="btn-secondary text-sm">
            <Plus size={16} /> Task Campaign
          </Link>
        </div>
      </div>

      <div className="flex justify-center mb-6">
        <div style={campaignRowWidth ? { width: campaignRowWidth } : undefined}>
          <Link to="/advertiser/campaigns" className="btn-secondary text-sm w-full">
            <ListChecks size={16} /> My Campaigns
          </Link>
        </div>
      </div>
    </div>
  );
}
