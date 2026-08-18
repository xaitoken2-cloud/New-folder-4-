import { useState, useEffect, useCallback } from 'react';
import {
  Gift, Loader2, MousePointerClick, CheckCircle2, Clock,
  RotateCcw, DollarSign, TrendingUp, Inbox, Server, RefreshCw,
} from 'lucide-react';
import type { OfferAdminStats, OfferAdminSession, OfferProviderAdmin } from '@/types';
import {
  offerAdminStats, offerAdminListSessions, offerAdminListProviders,
  offerAdminUpdateProvider, offerAdminCreateProvider, offerAdminSetProviderSecret,
  offerAdminTriggerSync,
  getErrorMessage,
} from '@/lib/api';
import { useToast } from '@/lib/toast';
import { formatMoney, formatDate, classNames } from '@/lib/format';
import { PageHeader, StatCard, EmptyState, ErrorState, Modal, Badge } from '@/components/ui';

type StatusFilter = 'all' | 'pending' | 'completed' | 'reversed';

function statusBadge(status: string): 'success' | 'warning' | 'danger' | 'neutral' {
  switch (status) {
    case 'completed': return 'success';
    case 'reversed':
    case 'rejected': return 'danger';
    case 'pending':
    case 'started':
    case 'clicked': return 'warning';
    default: return 'neutral';
  }
}

function AdminSessionRow({ session }: { session: OfferAdminSession }) {
  return (
    <div className="flex items-start gap-3 py-3 border-b border-ink-700 last:border-0 text-xs">
      <div className="w-8 h-8 rounded-lg bg-ink-800 flex items-center justify-center shrink-0">
        <Gift size={14} className="text-gray-500" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-medium text-gray-200 truncate">{session.offer_title || session.provider_offer_id}</span>
          <Badge variant={statusBadge(session.status)}>{session.status}</Badge>
        </div>
        <div className="flex items-center gap-2 mt-0.5 flex-wrap text-gray-500">
          <span>{session.username}</span>
          <span className="text-gray-600">•</span>
          <span>{session.provider_slug}</span>
          <span className="text-gray-600">•</span>
          <span className="capitalize">{session.offer_type.replace('_', ' ')}</span>
        </div>
        <div className="flex items-center gap-2 mt-0.5 flex-wrap text-gray-600 text-[10px]">
          <span>Click: {formatDate(session.created_at)}</span>
          {session.completed_at && <span>• Completed: {formatDate(session.completed_at)}</span>}
          {session.reversed_at && <span>• Reversed: {formatDate(session.reversed_at)}</span>}
        </div>
        {session.provider_conversion_id && (
          <div className="text-[10px] text-gray-600 mt-0.5 font-mono truncate">
            Conv ID: {session.provider_conversion_id}
          </div>
        )}
      </div>
      <div className="text-right shrink-0">
        <div className={classNames(
          'font-bold font-mono',
          session.status === 'reversed' ? 'text-danger-500' : 'text-success-500'
        )}>
          {session.status === 'reversed' ? '-' : '+'}{formatMoney(session.reward)}
        </div>
        {session.revenue > 0 && (
          <div className="text-[10px] text-gray-600">Rev: {formatMoney(session.revenue)}</div>
        )}
      </div>
    </div>
  );
}

function ProviderRow({
  provider,
  onToggle,
  onEdit,
  onSecret,
  onSync,
  syncing,
}: {
  provider: OfferProviderAdmin;
  onToggle: () => void;
  onEdit: () => void;
  onSecret: (type: 'api_key' | 'postback_secret') => void;
  onSync: () => void;
  syncing: boolean;
}) {
  return (
    <div className="flex items-center gap-3 py-3 border-b border-ink-700 last:border-0">
      <div className="w-9 h-9 rounded-lg bg-ink-800 flex items-center justify-center shrink-0">
        <Server size={15} className="text-gray-500" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-gray-200 truncate">{provider.display_name}</span>
          <Badge variant={provider.enabled ? 'success' : 'neutral'}>
            {provider.enabled ? 'Enabled' : 'Disabled'}
          </Badge>
        </div>
        <div className="flex items-center gap-2 mt-0.5 flex-wrap text-[11px] text-gray-500">
          <span className="font-mono">{provider.slug}</span>
          <span className="text-gray-600">•</span>
          <span className="capitalize">{provider.provider_type}</span>
          <span className="text-gray-600">•</span>
          <span>Margin: {provider.reward_margin_percent}%</span>
        </div>
        <div className="flex items-center gap-3 mt-1 text-[10px]">
          <span className={classNames('flex items-center gap-1', provider.has_api_key ? 'text-success-500' : 'text-gray-600')}>
            <CheckCircle2 size={10} /> API Key {provider.has_api_key ? 'Set' : 'Not Set'}
          </span>
          <span className={classNames('flex items-center gap-1', provider.has_postback_secret ? 'text-success-500' : 'text-gray-600')}>
            <CheckCircle2 size={10} /> Postback Secret {provider.has_postback_secret ? 'Set' : 'Not Set'}
          </span>
        </div>
        <div className="text-[10px] text-gray-600 mt-1">
          {provider.last_synced_at
            ? `Last synced: ${formatDate(provider.last_synced_at)}`
            : 'Never synced'}
        </div>
      </div>
      <div className="flex items-center gap-1.5 shrink-0">
        <button
          onClick={onSync}
          disabled={syncing || !provider.enabled}
          className="text-[10px] px-2 py-1 rounded bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700 transition-colors disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
        >
          {syncing ? <Loader2 size={10} className="animate-spin" /> : <RefreshCw size={10} />}
          Sync Now
        </button>
        <button onClick={onSecret.bind(null, 'api_key')} className="text-[10px] px-2 py-1 rounded bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700 transition-colors">
          API Key
        </button>
        <button onClick={onSecret.bind(null, 'postback_secret')} className="text-[10px] px-2 py-1 rounded bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700 transition-colors">
          Secret
        </button>
        <button onClick={onEdit} className="text-[10px] px-2 py-1 rounded bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700 transition-colors">
          Edit
        </button>
        <button
          onClick={onToggle}
          className={classNames(
            'text-[10px] px-2 py-1 rounded transition-colors',
            provider.enabled
              ? 'bg-danger-500/10 text-danger-500 hover:bg-danger-500/20'
              : 'bg-success-500/10 text-success-500 hover:bg-success-500/20'
          )}
        >
          {provider.enabled ? 'Disable' : 'Enable'}
        </button>
      </div>
    </div>
  );
}

export function AdminOffersPage() {
  const { toast } = useToast();
  const [stats, setStats] = useState<OfferAdminStats | null>(null);
  const [sessions, setSessions] = useState<OfferAdminSession[]>([]);
  const [providers, setProviders] = useState<OfferProviderAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [view, setView] = useState<'sessions' | 'providers'>('sessions');

  const [secretModal, setSecretModal] = useState<{ provider: OfferProviderAdmin; type: 'api_key' | 'postback_secret' } | null>(null);
  const [secretValue, setSecretValue] = useState('');
  const [editModal, setEditModal] = useState<OfferProviderAdmin | null>(null);
  const [editForm, setEditForm] = useState({ displayName: '', publisherId: '', rewardMargin: 100 });
  const [createModal, setCreateModal] = useState(false);
  const [createForm, setCreateForm] = useState({ slug: '', displayName: '', type: 'offerwall', publisherId: '', rewardMargin: 100 });
  const [actionLoading, setActionLoading] = useState(false);
  const [syncingSlug, setSyncingSlug] = useState<string | null>(null);

  const loadAll = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [s, sess, provs] = await Promise.all([
        offerAdminStats(),
        offerAdminListSessions({ status: statusFilter === 'all' ? null : statusFilter, limit: 200 }),
        offerAdminListProviders(),
      ]);
      setStats(s);
      setSessions(sess);
      setProviders(provs);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load offer data'));
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => {
    loadAll();
  }, [loadAll]);

  const handleSyncProvider = async (provider: OfferProviderAdmin) => {
    setSyncingSlug(provider.slug);
    try {
      const result = await offerAdminTriggerSync(provider.slug);
      if (result.ok) {
        toast(result.message || `Synced ${result.synced ?? 0} offers`, 'success');
      } else {
        toast(result.error || 'Sync failed', 'error');
      }
      loadAll();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to sync provider'), 'error');
    } finally {
      setSyncingSlug(null);
    }
  };

  const handleToggleProvider = async (provider: OfferProviderAdmin) => {
    try {
      await offerAdminUpdateProvider({
        providerId: provider.id,
        enabled: !provider.enabled,
      });
      toast(`Provider ${provider.enabled ? 'disabled' : 'enabled'}`, 'success');
      loadAll();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to update provider'), 'error');
    }
  };

  const handleSaveSecret = async () => {
    if (!secretModal || !secretValue.trim()) return;
    setActionLoading(true);
    try {
      await offerAdminSetProviderSecret({
        providerId: secretModal.provider.id,
        secretType: secretModal.type,
        secretValue: secretValue.trim(),
      });
      toast(`${secretModal.type === 'api_key' ? 'API key' : 'Postback secret'} saved`, 'success');
      setSecretModal(null);
      setSecretValue('');
      loadAll();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to save secret'), 'error');
    } finally {
      setActionLoading(false);
    }
  };

  const handleSaveEdit = async () => {
    if (!editModal) return;
    setActionLoading(true);
    try {
      await offerAdminUpdateProvider({
        providerId: editModal.id,
        displayName: editForm.displayName,
        publisherId: editForm.publisherId,
        rewardMarginPercent: editForm.rewardMargin,
      });
      toast('Provider updated', 'success');
      setEditModal(null);
      loadAll();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to update provider'), 'error');
    } finally {
      setActionLoading(false);
    }
  };

  const handleCreateProvider = async () => {
    if (!createForm.slug.trim() || !createForm.displayName.trim()) return;
    setActionLoading(true);
    try {
      await offerAdminCreateProvider({
        slug: createForm.slug.trim().toLowerCase(),
        displayName: createForm.displayName.trim(),
        providerType: createForm.type,
        publisherId: createForm.publisherId.trim(),
        rewardMarginPercent: createForm.rewardMargin,
      });
      toast('Provider created (disabled). Configure credentials then enable.', 'success');
      setCreateModal(false);
      setCreateForm({ slug: '', displayName: '', type: 'offerwall', publisherId: '', rewardMargin: 100 });
      loadAll();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to create provider'), 'error');
    } finally {
      setActionLoading(false);
    }
  };

  return (
    <div>
      <PageHeader
        title="Offer Management"
        subtitle="Monitor offer conversions, manage providers, and view statistics."
        action={
          <button onClick={() => setCreateModal(true)} className="btn-secondary text-xs">
            Add Provider
          </button>
        }
      />

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mb-5">
          <StatCard label="Total Clicks" value={stats.total_clicks} icon={<MousePointerClick size={16} />} accent="neutral" />
          <StatCard label="Pending" value={stats.pending} icon={<Clock size={16} />} accent="brand" />
          <StatCard label="Completed" value={stats.completed} icon={<CheckCircle2 size={16} />} accent="green" />
          <StatCard label="Reversed" value={stats.reversed} icon={<RotateCcw size={16} />} accent="red" />
          <StatCard label="Total Rewards" value={formatMoney(stats.total_rewards)} icon={<DollarSign size={16} />} accent="green" />
          <StatCard label="Total Revenue" value={formatMoney(stats.total_revenue)} icon={<TrendingUp size={16} />} accent="brand" />
          <StatCard label="Active Providers" value={`${stats.active_providers}/${stats.total_providers}`} icon={<Server size={16} />} accent="neutral" />
          <StatCard label="Active Offers" value={stats.total_offers} icon={<Gift size={16} />} accent="brand" />
        </div>
      )}

      {/* View toggle */}
      <div className="flex items-center gap-1.5 mb-4">
        <button
          onClick={() => setView('sessions')}
          className={classNames(
            'px-3.5 py-2 rounded-lg text-xs font-medium transition-colors',
            view === 'sessions' ? 'bg-brand-500 text-ink-950' : 'bg-ink-800 text-gray-400 hover:bg-ink-700'
          )}
        >
          Conversions
        </button>
        <button
          onClick={() => setView('providers')}
          className={classNames(
            'px-3.5 py-2 rounded-lg text-xs font-medium transition-colors',
            view === 'providers' ? 'bg-brand-500 text-ink-950' : 'bg-ink-800 text-gray-400 hover:bg-ink-700'
          )}
        >
          Providers
        </button>
        {view === 'sessions' && (
          <div className="flex items-center gap-1.5 ml-auto overflow-x-auto scrollbar-hide">
            {(['all', 'pending', 'completed', 'reversed'] as StatusFilter[]).map((f) => (
              <button
                key={f}
                onClick={() => setStatusFilter(f)}
                className={classNames(
                  'px-3 py-1.5 rounded-lg text-[11px] font-medium whitespace-nowrap transition-colors',
                  statusFilter === f ? 'bg-ink-700 text-gray-200' : 'bg-ink-800 text-gray-500 hover:text-gray-300'
                )}
              >
                {f.charAt(0).toUpperCase() + f.slice(1)}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Content */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 size={28} className="animate-spin text-brand-500" />
        </div>
      ) : error ? (
        <ErrorState message={error} onRetry={loadAll} />
      ) : view === 'sessions' ? (
        sessions.length === 0 ? (
          <EmptyState title="No offer sessions" message="Offer clicks and conversions will appear here." icon={<Inbox size={24} />} />
        ) : (
          <div className="card p-4 sm:p-5">
            {sessions.map((s) => <AdminSessionRow key={s.id} session={s} />)}
          </div>
        )
      ) : (
        <div className="card p-4 sm:p-5">
          {providers.length === 0 ? (
            <EmptyState title="No providers configured" message="Add an offer provider to get started. Providers stay disabled until credentials are set." icon={<Server size={24} />} />
          ) : (
            providers.map((p) => (
              <ProviderRow
                key={p.id}
                provider={p}
                syncing={syncingSlug === p.slug}
                onSync={() => handleSyncProvider(p)}
                onToggle={() => handleToggleProvider(p)}
                onEdit={() => {
                  setEditModal(p);
                  setEditForm({ displayName: p.display_name, publisherId: p.publisher_id, rewardMargin: p.reward_margin_percent });
                }}
                onSecret={(type) => {
                  setSecretModal({ provider: p, type });
                  setSecretValue('');
                }}
              />
            ))
          )}
        </div>
      )}

      {/* Secret modal */}
      <Modal open={!!secretModal} onClose={() => setSecretModal(null)} title={`Set ${secretModal?.type === 'api_key' ? 'API Key' : 'Postback Secret'}`}>
        <div className="space-y-4">
          <p className="text-sm text-gray-400">
            Enter the {secretModal?.type === 'api_key' ? 'API key' : 'postback secret'} for{' '}
            <span className="text-gray-200 font-medium">{secretModal?.provider.display_name}</span>.
            The value is encrypted server-side and never exposed to the browser.
          </p>
          <input
            type="password"
            value={secretValue}
            onChange={(e) => setSecretValue(e.target.value)}
            placeholder={secretModal?.type === 'api_key' ? 'Paste API key...' : 'Paste postback secret...'}
            className="input-field"
            autoFocus
          />
          <div className="flex gap-3 justify-end">
            <button onClick={() => setSecretModal(null)} className="btn-secondary">Cancel</button>
            <button onClick={handleSaveSecret} disabled={actionLoading || !secretValue.trim()} className="btn-primary">
              {actionLoading ? <Loader2 size={14} className="animate-spin" /> : 'Save'}
            </button>
          </div>
        </div>
      </Modal>

      {/* Edit modal */}
      <Modal open={!!editModal} onClose={() => setEditModal(null)} title={`Edit ${editModal?.display_name}`}>
        <div className="space-y-4">
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Display Name</label>
            <input
              type="text"
              value={editForm.displayName}
              onChange={(e) => setEditForm({ ...editForm, displayName: e.target.value })}
              className="input-field"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Publisher ID</label>
            <input
              type="text"
              value={editForm.publisherId}
              onChange={(e) => setEditForm({ ...editForm, publisherId: e.target.value })}
              className="input-field"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Reward Margin (%)</label>
            <input
              type="number"
              min="0"
              max="100"
              value={editForm.rewardMargin}
              onChange={(e) => setEditForm({ ...editForm, rewardMargin: parseFloat(e.target.value) || 100 })}
              className="input-field"
            />
            <p className="text-[10px] text-gray-600 mt-1">Percent of provider reward passed to users.</p>
          </div>
          <div className="flex gap-3 justify-end">
            <button onClick={() => setEditModal(null)} className="btn-secondary">Cancel</button>
            <button onClick={handleSaveEdit} disabled={actionLoading} className="btn-primary">
              {actionLoading ? <Loader2 size={14} className="animate-spin" /> : 'Save'}
            </button>
          </div>
        </div>
      </Modal>

      {/* Create provider modal */}
      <Modal open={createModal} onClose={() => setCreateModal(false)} title="Add Offer Provider">
        <div className="space-y-4">
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Provider Slug</label>
            <input
              type="text"
              value={createForm.slug}
              onChange={(e) => setCreateForm({ ...createForm, slug: e.target.value })}
              placeholder="e.g. adgem, offertoro, cpx_research"
              className="input-field"
            />
            <p className="text-[10px] text-gray-600 mt-1">Unique identifier used in webhook URLs.</p>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Display Name</label>
            <input
              type="text"
              value={createForm.displayName}
              onChange={(e) => setCreateForm({ ...createForm, displayName: e.target.value })}
              placeholder="e.g. AdGem, OfferToro"
              className="input-field"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Provider Type</label>
            <select
              value={createForm.type}
              onChange={(e) => setCreateForm({ ...createForm, type: e.target.value })}
              className="input-field"
            >
              <option value="offerwall">Offerwall</option>
              <option value="survey">Survey</option>
              <option value="app_install">App Install</option>
              <option value="game">Game</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Publisher ID</label>
            <input
              type="text"
              value={createForm.publisherId}
              onChange={(e) => setCreateForm({ ...createForm, publisherId: e.target.value })}
              placeholder="Your publisher/affiliate ID"
              className="input-field"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Reward Margin (%)</label>
            <input
              type="number"
              min="0"
              max="100"
              value={createForm.rewardMargin}
              onChange={(e) => setCreateForm({ ...createForm, rewardMargin: parseFloat(e.target.value) || 100 })}
              className="input-field"
            />
          </div>
          <p className="text-xs text-gray-500 bg-ink-800/50 rounded-lg p-3">
            The provider is created disabled. Set the API key and postback secret, then enable it.
          </p>
          <div className="flex gap-3 justify-end">
            <button onClick={() => setCreateModal(false)} className="btn-secondary">Cancel</button>
            <button onClick={handleCreateProvider} disabled={actionLoading || !createForm.slug.trim() || !createForm.displayName.trim()} className="btn-primary">
              {actionLoading ? <Loader2 size={14} className="animate-spin" /> : 'Create'}
            </button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
