import { useEffect, useState } from 'react';
import { Link } from '@/lib/router';
import { adListCampaigns, adPauseCampaign, adResumeCampaign, adStopCampaign, getErrorMessage } from '@/lib/api';
import { useToast } from '@/lib/toast';
import { LoadingScreen, ErrorState, PageHeader, Badge, EmptyState, ConfirmDialog } from '@/components/ui';
import { formatMoney, classNames } from '@/lib/format';
import { COUNTRY_NAME_MAP } from '@/lib/countries';
import {
  MousePointerClick, ListChecks, Pause, Play, Square, Eye, CheckCircle2,
} from 'lucide-react';
import type { AdCampaignsResult, CampaignStatus } from '@/types';

type CampaignTab = 'all' | 'ptc' | 'task';
const TAB_LABELS: Record<CampaignTab, string> = {
  all: 'All',
  ptc: 'PTC Campaigns',
  task: 'Task Campaigns',
};

const statusVariant: Record<CampaignStatus, 'brand' | 'success' | 'warning' | 'danger' | 'neutral'> = {
  draft: 'neutral',
  pending: 'warning',
  active: 'success',
  paused: 'brand',
  completed: 'neutral',
  rejected: 'danger',
};

export function AdCampaignsPage() {
  const { toast } = useToast();
  const [campaigns, setCampaigns] = useState<AdCampaignsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [stopTarget, setStopTarget] = useState<{ id: string; type: 'ptc' | 'task'; title: string } | null>(null);
  const [activeTab, setActiveTab] = useState<CampaignTab>('all');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const data = await adListCampaigns();
      setCampaigns(data);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load campaigns'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handlePause = async (id: string, type: 'ptc' | 'task') => {
    setActionLoading(id);
    try {
      await adPauseCampaign(id, type);
      toast('Campaign paused', 'success');
      await load();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to pause'), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  const handleResume = async (id: string, type: 'ptc' | 'task') => {
    setActionLoading(id);
    try {
      await adResumeCampaign(id, type);
      toast('Campaign resumed', 'success');
      await load();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to resume'), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  const handleStop = async () => {
    if (!stopTarget) return;
    setActionLoading(stopTarget.id);
    try {
      const result = await adStopCampaign(stopTarget.id, stopTarget.type);
      const refund = (result as { refund?: number })?.refund ?? 0;
      toast(`Campaign stopped. Refunded ${formatMoney(refund)} to advertising balance.`, 'success');
      setStopTarget(null);
      await load();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to stop campaign'), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) return <LoadingScreen label="Loading campaigns..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!campaigns) return null;

  const ptcCampaigns = campaigns.ptc_campaigns ?? [];
  const taskCampaigns = campaigns.task_campaigns ?? [];

  if (ptcCampaigns.length === 0 && taskCampaigns.length === 0) {
    return (
      <div>
        <PageHeader title="My Campaigns" subtitle="Manage your advertising campaigns" />
        <EmptyState
          title="No campaigns yet"
          message="Create a PTC or task campaign to get started."
          icon={<MousePointerClick size={24} />}
        />
        <div className="flex gap-2 justify-center mt-4">
          <Link to="/advertiser/create-ptc" className="btn-primary text-sm">Create PTC Campaign</Link>
          <Link to="/advertiser/create-task" className="btn-secondary text-sm">Create Task Campaign</Link>
        </div>
      </div>
    );
  }

  return (
    <div>
      <PageHeader
        title="My Campaigns"
        subtitle="Manage your advertising campaigns"
        action={
          <div className="flex gap-2">
            <Link to="/advertiser/create-ptc" className="btn-primary text-sm">New PTC</Link>
            <Link to="/advertiser/create-task" className="btn-secondary text-sm">New Task</Link>
          </div>
        }
      />

      <div className="flex items-center gap-1.5 mb-5 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
        {(Object.keys(TAB_LABELS) as CampaignTab[]).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={classNames(
              'px-3.5 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition-colors',
              activeTab === tab
                ? 'bg-brand-500 text-ink-950'
                : 'bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700'
            )}
          >
            {TAB_LABELS[tab]}
          </button>
        ))}
      </div>

      {/* PTC Campaigns */}
      {ptcCampaigns.length > 0 && (activeTab === 'all' || activeTab === 'ptc') && (
        <div className="mb-6">
          <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
            <MousePointerClick size={16} /> PTC Campaigns
          </h2>
          <div className="space-y-3">
            {ptcCampaigns.map((c) => {
              const remaining = c.budget - c.spent;
              const pct = c.budget > 0 ? (c.spent / c.budget) * 100 : 0;
              return (
                <div key={c.id} className="card p-4">
                  <div className="flex items-start justify-between mb-3">
                    <div>
                      <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                      <div className="flex items-center gap-2 mt-1">
                        <Badge variant={statusVariant[c.status]}>{c.status}</Badge>
                        <span className="text-xs text-gray-500">PTC Ad</span>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-xs text-gray-500">Remaining</div>
                      <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(remaining)}</div>
                    </div>
                  </div>

                  <div className="grid grid-cols-4 gap-3 mb-3 text-xs">
                    <div>
                      <span className="text-gray-500">Budget</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.budget)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Spent</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.spent)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Reward</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Views</span>
                      <p className="text-gray-300 font-mono flex items-center gap-1"><Eye size={11} /> {c.total_views}</p>
                    </div>
                  </div>

                  <div className="flex items-center gap-3 mb-3">
                    <div className="flex-1 h-1.5 rounded-full bg-ink-700 overflow-hidden">
                      <div className="h-full brand-gradient rounded-full" style={{ width: `${Math.min(100, pct)}%` }} />
                    </div>
                    <span className="text-xs text-gray-500 font-mono">{pct.toFixed(1)}%</span>
                  </div>

                  <div className="flex flex-wrap gap-x-4 gap-y-1 mb-3 text-xs text-gray-400">
                    <span>
                      <span className="text-gray-500">Countries:</span>{' '}
                      {c.target_all_countries || (c.target_countries ?? []).length === 0
                        ? 'Worldwide'
                        : (c.target_countries ?? []).map((code) => COUNTRY_NAME_MAP[code] ?? code).join(', ')}
                    </span>
                    <span>
                      <span className="text-gray-500">Devices:</span>{' '}
                      {(c.target_devices ?? []).length >= 3
                        ? 'All Devices'
                        : (c.target_devices ?? []).map((d) => d.charAt(0).toUpperCase() + d.slice(1)).join(' + ')}
                    </span>
                  </div>

                  {(c.status === 'active' || c.status === 'paused') && (
                    <div className="flex gap-2">
                      {c.status === 'active' && (
                        <button onClick={() => handlePause(c.id, 'ptc')} disabled={actionLoading === c.id} className="btn-secondary text-xs">
                          <Pause size={14} /> Pause
                        </button>
                      )}
                      {c.status === 'paused' && (
                        <button onClick={() => handleResume(c.id, 'ptc')} disabled={actionLoading === c.id} className="btn-secondary text-xs">
                          <Play size={14} /> Resume
                        </button>
                      )}
                      <button onClick={() => setStopTarget({ id: c.id, type: 'ptc', title: c.title })} disabled={actionLoading === c.id} className="btn-danger text-xs">
                        <Square size={14} /> Stop
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Task Campaigns */}
      {taskCampaigns.length > 0 && (activeTab === 'all' || activeTab === 'task') && (
        <div className="mb-6">
          <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
            <ListChecks size={16} /> Task Campaigns
          </h2>
          <div className="space-y-3">
            {taskCampaigns.map((c) => {
              const remaining = c.budget - c.spent;
              const pct = c.budget > 0 ? (c.spent / c.budget) * 100 : 0;
              return (
                <div key={c.id} className="card p-4">
                  <div className="flex items-start justify-between mb-3">
                    <div>
                      <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                      <div className="flex items-center gap-2 mt-1">
                        <Badge variant={statusVariant[c.status]}>{c.status}</Badge>
                        <span className="text-xs text-gray-500 capitalize">{c.task_type.replace('_', ' ')}</span>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-xs text-gray-500">Remaining</div>
                      <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(remaining)}</div>
                    </div>
                  </div>

                  <div className="grid grid-cols-4 gap-3 mb-3 text-xs">
                    <div>
                      <span className="text-gray-500">Budget</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.budget)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Spent</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.spent)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Reward</span>
                      <p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Completions</span>
                      <p className="text-gray-300 font-mono flex items-center gap-1"><CheckCircle2 size={11} /> {c.total_completions}</p>
                    </div>
                  </div>

                  <div className="flex items-center gap-3 mb-3">
                    <div className="flex-1 h-1.5 rounded-full bg-ink-700 overflow-hidden">
                      <div className="h-full brand-gradient rounded-full" style={{ width: `${Math.min(100, pct)}%` }} />
                    </div>
                    <span className="text-xs text-gray-500 font-mono">{pct.toFixed(1)}%</span>
                  </div>

                  {(c.status === 'active' || c.status === 'paused') && (
                    <div className="flex gap-2">
                      {c.status === 'active' && (
                        <button onClick={() => handlePause(c.id, 'task')} disabled={actionLoading === c.id} className="btn-secondary text-xs">
                          <Pause size={14} /> Pause
                        </button>
                      )}
                      {c.status === 'paused' && (
                        <button onClick={() => handleResume(c.id, 'task')} disabled={actionLoading === c.id} className="btn-secondary text-xs">
                          <Play size={14} /> Resume
                        </button>
                      )}
                      <button onClick={() => setStopTarget({ id: c.id, type: 'task', title: c.title })} disabled={actionLoading === c.id} className="btn-danger text-xs">
                        <Square size={14} /> Stop
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      <ConfirmDialog
        open={!!stopTarget}
        onClose={() => setStopTarget(null)}
        onConfirm={handleStop}
        title="Stop Campaign"
        message={`Stop "${stopTarget?.title}"? Unspent budget will be refunded to your advertising balance. This cannot be undone.`}
        confirmLabel="Stop & Refund"
        danger
      />
    </div>
  );
}
