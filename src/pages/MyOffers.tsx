import { useState, useEffect, useCallback } from 'react';
import {
  Gift, Loader2, CheckCircle2, Clock, XCircle, RotateCcw,
  Inbox,
} from 'lucide-react';
import type { OfferSession, OfferSessionStatus } from '@/types';
import { offerListMySessions, getErrorMessage } from '@/lib/api';
import { formatMoney, formatXc, formatDate, classNames } from '@/lib/format';
import { PageHeader, EmptyState, ErrorState } from '@/components/ui';

type Filter = 'all' | 'pending' | 'completed' | 'reversed';

const FILTERS: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'completed', label: 'Completed' },
  { key: 'reversed', label: 'Reversed' },
];

function statusIcon(status: OfferSessionStatus) {
  switch (status) {
    case 'completed': return <CheckCircle2 size={14} className="text-success-500" />;
    case 'reversed': return <RotateCcw size={14} className="text-danger-500" />;
    case 'rejected': return <XCircle size={14} className="text-danger-500" />;
    case 'pending': return <Clock size={14} className="text-warning-500" />;
    case 'started': return <Clock size={14} className="text-warning-500" />;
    default: return <Clock size={14} className="text-gray-500" />;
  }
}

function statusColor(status: OfferSessionStatus): string {
  switch (status) {
    case 'completed': return 'text-success-500';
    case 'reversed': return 'text-danger-500';
    case 'rejected': return 'text-danger-500';
    case 'pending':
    case 'started':
    case 'clicked': return 'text-warning-500';
    default: return 'text-gray-500';
  }
}

function statusLabel(status: OfferSessionStatus): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function SessionRow({ session }: { session: OfferSession }) {
  return (
    <div className="flex items-start gap-3 py-3.5 border-b border-ink-700 last:border-0">
      <div className="w-10 h-10 rounded-lg bg-ink-800 flex items-center justify-center shrink-0 overflow-hidden">
        {session.offer_icon ? (
          <img src={session.offer_icon} alt="" className="w-full h-full object-cover" />
        ) : (
          <Gift size={16} className="text-gray-500" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-gray-200 truncate">
            {session.offer_title || session.provider_offer_id}
          </span>
        </div>
        <div className="flex items-center gap-2 mt-0.5 flex-wrap">
          <span className="text-[11px] text-gray-500">{session.provider_slug}</span>
          <span className="text-gray-600 text-[10px]">•</span>
          <span className="text-[11px] text-gray-500 capitalize">{session.offer_type.replace('_', ' ')}</span>
        </div>
        <div className="flex items-center gap-2 mt-1.5 flex-wrap">
          <span className={classNames('flex items-center gap-1 text-[11px] font-medium', statusColor(session.status))}>
            {statusIcon(session.status)} {statusLabel(session.status)}
          </span>
          <span className="text-gray-600 text-[10px]">•</span>
          <span className="text-[11px] text-gray-500">{formatDate(session.created_at)}</span>
          {session.completed_at && (
            <>
              <span className="text-gray-600 text-[10px]">•</span>
              <span className="text-[11px] text-gray-500">Completed {formatDate(session.completed_at)}</span>
            </>
          )}
        </div>
        {session.provider_conversion_id && (
          <div className="text-[10px] text-gray-600 mt-1 font-mono truncate">
            ID: {session.provider_conversion_id}
          </div>
        )}
      </div>
      <div className="text-right shrink-0">
        <div className={classNames(
          'text-sm font-bold font-mono',
          session.status === 'reversed' ? 'text-danger-500' : 'text-success-500'
        )}>
          {session.status === 'reversed' ? '-' : '+'}{formatXc(session.reward)} XC
        </div>
      </div>
    </div>
  );
}

export function MyOffersPage() {
  const [filter, setFilter] = useState<Filter>('all');
  const [sessions, setSessions] = useState<OfferSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadSessions = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await offerListMySessions(filter, 100, 0);
      setSessions(data);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load offer history'));
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  return (
    <div>
      <PageHeader
        title="My Offers"
        subtitle="Track your offer completions, pending conversions, and rewards."
      />

      {/* Filters */}
      <div className="flex items-center gap-1.5 mb-4 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={classNames(
              'px-3.5 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition-colors',
              filter === f.key
                ? 'bg-brand-500 text-ink-950'
                : 'bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700'
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* Content */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 size={28} className="animate-spin text-brand-500" />
        </div>
      ) : error ? (
        <ErrorState message={error} onRetry={loadSessions} />
      ) : sessions.length === 0 ? (
        <EmptyState
          title="No offers yet"
          message="When you start offers, they will appear here with their status and reward."
          icon={<Inbox size={24} />}
        />
      ) : (
        <div className="card p-4 sm:p-5">
          {sessions.map((session) => (
            <SessionRow key={session.id} session={session} />
          ))}
        </div>
      )}
    </div>
  );
}
