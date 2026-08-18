import { useEffect, useState, useCallback } from 'react';
import { Link } from '@/lib/router';
import { getDashboard, listPtcAds, listTasks, listTransactions, offerListAvailable, offerStartSession, getErrorMessage } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { LoadingScreen, ErrorState, StatCard, PageHeader, Badge, Modal, EmptyState } from '@/components/ui';
import { formatMoney, formatXc, timeAgo, classNames } from '@/lib/format';
import { useToast } from '@/lib/toast';
import {
  Wallet, TrendingUp, DollarSign, Activity, Coins,
  Gift, Clock, Star, Smartphone, Globe, Apple,
  ExternalLink, AlertCircle, Loader2, Filter,
} from 'lucide-react';
import type { DashboardData, PtcAd, Task, Transaction, Offer, OfferType, OfferPlatform } from '@/types';

type OfferTab = 'all' | 'survey' | 'app_install' | 'game';

const OFFER_TAB_LABELS: Record<OfferTab, string> = {
  all: 'All',
  survey: 'Surveys',
  app_install: 'Apps',
  game: 'Games',
};

function platformIcon(platform: OfferPlatform) {
  if (platform === 'android') return <Smartphone size={12} />;
  if (platform === 'ios') return <Apple size={12} />;
  if (platform === 'web') return <Globe size={12} />;
  return null;
}

function platformLabel(platform: OfferPlatform): string {
  switch (platform) {
    case 'android': return 'Android';
    case 'ios': return 'iOS';
    case 'web': return 'Web';
    default: return 'All Platforms';
  }
}

function typeBadgeVariant(offerType: OfferType): 'brand' | 'success' | 'warning' | 'neutral' {
  switch (offerType) {
    case 'survey': return 'brand';
    case 'app_install': return 'success';
    case 'game': return 'warning';
    default: return 'neutral';
  }
}

function typeLabel(offerType: OfferType): string {
  switch (offerType) {
    case 'survey': return 'Survey';
    case 'app_install': return 'App Install';
    case 'game': return 'Game';
    case 'signup': return 'Signup';
    case 'trial': return 'Trial';
    default: return 'Offer';
  }
}

function OfferCard({ offer, onStart }: { offer: Offer; onStart: (offer: Offer) => void }) {
  return (
    <div className="card p-4 sm:p-5 flex flex-col gap-3 hover:border-ink-600 transition-colors group">
      <div className="flex items-start gap-3">
        <div className="w-11 h-11 sm:w-12 sm:h-12 rounded-xl bg-ink-700 flex items-center justify-center shrink-0 overflow-hidden">
          {offer.icon_url ? (
            <img src={offer.icon_url} alt="" className="w-full h-full object-cover" />
          ) : (
            <Gift size={20} className="text-gray-500" />
          )}
        </div>
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-semibold text-gray-100 leading-tight line-clamp-2">{offer.title}</h3>
          <div className="flex items-center gap-1.5 mt-1 flex-wrap">
            <Badge variant={typeBadgeVariant(offer.offer_type)}>{typeLabel(offer.offer_type)}</Badge>
            {offer.platform !== 'all' && (
              <span className="flex items-center gap-1 text-[10px] text-gray-500 bg-ink-800 px-1.5 py-0.5 rounded">
                {platformIcon(offer.platform)}
                {platformLabel(offer.platform)}
              </span>
            )}
          </div>
        </div>
      </div>

      {offer.description && (
        <p className="text-xs text-gray-500 line-clamp-2 leading-relaxed">{offer.description}</p>
      )}

      <div className="flex items-center gap-3 text-[11px] text-gray-500 flex-wrap">
        {offer.estimated_time_minutes > 0 && (
          <span className="flex items-center gap-1">
            <Clock size={11} /> {offer.estimated_time_minutes} min
          </span>
        )}
        {offer.difficulty && offer.difficulty !== 'easy' && (
          <span className="flex items-center gap-1">
            <Star size={11} /> {offer.difficulty}
          </span>
        )}
        <span className="text-gray-600">{offer.provider_name}</span>
      </div>

      <div className="flex items-center justify-between gap-2 mt-auto pt-1">
        <div>
          <div className="text-lg font-bold text-success-500 font-mono">
            +{formatXc(offer.reward)} <span className="text-[10px] text-gray-500">XC</span>
          </div>
        </div>
        <button
          onClick={() => onStart(offer)}
          className="btn-primary text-xs px-3 py-2 flex items-center gap-1.5 whitespace-nowrap"
        >
          Start Offer
          <ExternalLink size={13} />
        </button>
      </div>
    </div>
  );
}

function OfferDetailModal({
  offer,
  open,
  onClose,
  onConfirm,
  loading,
}: {
  offer: Offer | null;
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  loading: boolean;
}) {
  if (!offer) return null;
  return (
    <Modal open={open} onClose={onClose} title={offer.title} maxWidth="max-w-lg">
      <div className="space-y-4">
        <div className="flex items-center gap-3">
          <div className="w-14 h-14 rounded-xl bg-ink-700 flex items-center justify-center shrink-0 overflow-hidden">
            {offer.icon_url ? (
              <img src={offer.icon_url} alt="" className="w-full h-full object-cover" />
            ) : (
              <Gift size={24} className="text-gray-500" />
            )}
          </div>
          <div>
            <Badge variant={typeBadgeVariant(offer.offer_type)}>{typeLabel(offer.offer_type)}</Badge>
            <div className="text-xs text-gray-500 mt-1">{offer.provider_name}</div>
          </div>
          <div className="ml-auto text-right">
            <div className="text-2xl font-bold text-success-500 font-mono">+{formatXc(offer.reward)} <span className="text-[10px] text-gray-500">XC</span></div>
            <div className="text-[10px] text-gray-500">{offer.currency_code} (converted to XC)</div>
          </div>
        </div>

        {offer.description && (
          <p className="text-sm text-gray-400 leading-relaxed">{offer.description}</p>
        )}

        <div className="grid grid-cols-2 gap-3 text-xs">
          {offer.estimated_time_minutes > 0 && (
            <div className="bg-ink-800/50 rounded-lg p-3">
              <div className="text-gray-500 mb-0.5">Est. Time</div>
              <div className="text-gray-200 font-medium flex items-center gap-1">
                <Clock size={12} /> {offer.estimated_time_minutes} min
              </div>
            </div>
          )}
          <div className="bg-ink-800/50 rounded-lg p-3">
            <div className="text-gray-500 mb-0.5">Platform</div>
            <div className="text-gray-200 font-medium flex items-center gap-1">
              {platformIcon(offer.platform)} {platformLabel(offer.platform)}
            </div>
          </div>
          {offer.difficulty && (
            <div className="bg-ink-800/50 rounded-lg p-3">
              <div className="text-gray-500 mb-0.5">Difficulty</div>
              <div className="text-gray-200 font-medium flex items-center gap-1">
                <Star size={12} /> {offer.difficulty}
              </div>
            </div>
          )}
          <div className="bg-ink-800/50 rounded-lg p-3">
            <div className="text-gray-500 mb-0.5">Provider</div>
            <div className="text-gray-200 font-medium truncate">{offer.provider_name}</div>
          </div>
        </div>

        {offer.requirements && (
          <div>
            <div className="text-xs font-semibold text-gray-300 mb-1.5">Requirements</div>
            <p className="text-xs text-gray-500 leading-relaxed whitespace-pre-line">{offer.requirements}</p>
          </div>
        )}

        <div className="bg-warning-500/5 border border-warning-500/20 rounded-lg p-3">
          <div className="flex items-start gap-2">
            <AlertCircle size={14} className="text-warning-500 shrink-0 mt-0.5" />
            <p className="text-xs text-gray-400 leading-relaxed">
              Make sure you meet the requirements and complete the offer on the same
              device/browser when required by the provider. Your reward is credited
              only after the provider confirms completion via a verified server callback.
              Qualification is not guaranteed.
            </p>
          </div>
        </div>

        <button
          onClick={onConfirm}
          disabled={loading}
          className="btn-primary w-full flex items-center justify-center gap-2"
        >
          {loading ? (
            <><Loader2 size={16} className="animate-spin" /> Starting...</>
          ) : (
            <>Start Offer <ExternalLink size={15} /></>
          )}
        </button>
      </div>
    </Modal>
  );
}

export function DashboardPage() {
  const { profile } = useAuth();
  const { toast } = useToast();
  const [data, setData] = useState<DashboardData | null>(null);
  const [ads, setAds] = useState<PtcAd[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [recentTx, setRecentTx] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [activeOfferTab, setActiveOfferTab] = useState<OfferTab>('all');
  const [offersList, setOffersList] = useState<Offer[]>([]);
  const [offersLoading, setOffersLoading] = useState(true);
  const [offersError, setOffersError] = useState<string | null>(null);
  const [selectedOffer, setSelectedOffer] = useState<Offer | null>(null);
  const [offerModalOpen, setOfferModalOpen] = useState(false);
  const [offerStarting, setOfferStarting] = useState(false);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [dash, adList, taskList, txResult] = await Promise.all([
        getDashboard(),
        listPtcAds(),
        listTasks(),
        listTransactions('earnings', 1, 5),
      ]);
      setData(dash);
      setAds(adList.slice(0, 3));
      setTasks(taskList.slice(0, 3));
      setRecentTx(txResult.data);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load dashboard'));
    } finally {
      setLoading(false);
    }
  };

  const loadOffers = useCallback(async () => {
    setOffersLoading(true);
    setOffersError(null);
    try {
      const result = await offerListAvailable(activeOfferTab, 'all');
      setOffersList(result);
    } catch (err) {
      setOffersError(getErrorMessage(err, 'Failed to load offers'));
    } finally {
      setOffersLoading(false);
    }
  }, [activeOfferTab]);

  useEffect(() => { load(); }, []);
  useEffect(() => { loadOffers(); }, [loadOffers]);

  const handleStartOfferClick = (offer: Offer) => {
    setSelectedOffer(offer);
    setOfferModalOpen(true);
  };

  const handleConfirmStartOffer = async () => {
    if (!selectedOffer) return;
    setOfferStarting(true);
    try {
      const result = await offerStartSession(selectedOffer.id);
      if (result.error) {
        toast(result.error, 'error');
        return;
      }
      setOfferModalOpen(false);
      toast('Opening offer... You will be credited after the provider confirms completion.', 'success');
      if (result.tracking_url) {
        window.open(result.tracking_url, '_blank', 'noopener,noreferrer');
      }
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to start offer'), 'error');
    } finally {
      setOfferStarting(false);
    }
  };

  if (loading) return <LoadingScreen label="Loading your dashboard..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return <ErrorState message="No data available" />;

  return (
    <div>
      <PageHeader
        title={`Welcome back, ${profile?.username}`}
        subtitle="Here's your earning overview"
      />

      {profile?.status !== 'active' && (
        <div className="card p-4 mb-6 border-danger-500/30 bg-danger-500/5">
          <p className="text-sm text-danger-500">
            Your account is currently <span className="font-semibold">{profile?.status}</span>. Some features may be restricted. Please contact support.
          </p>
        </div>
      )}

      {/* Stat cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mb-5 sm:mb-6">
        <StatCard label="XC Balance" value={`${formatXc(data.xc_balance)} XC`} icon={<Coins size={18} />} accent="brand" />
        <StatCard label="USD Balance" value={formatMoney(data.available_balance)} icon={<DollarSign size={18} />} accent="brand" />
        <StatCard label="Today's Earnings" value={`${formatXc(data.xc_today_earned ?? 0)} XC`} icon={<TrendingUp size={18} />} accent="purple" />
        <StatCard label="Total Earned" value={`${formatXc(data.xc_total_earned ?? 0)} XC`} icon={<Wallet size={18} />} accent="brand" />
      </div>

      {/* Offers */}
      <div className="card p-4 sm:p-5 mb-5 sm:mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold text-gray-300">Offers</h3>
          <Link to="/offers" className="text-xs text-brand-400 hover:text-brand-300">View all</Link>
        </div>
        <div className="flex items-center gap-1.5 mb-4 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
          {(Object.keys(OFFER_TAB_LABELS) as OfferTab[]).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveOfferTab(tab)}
              className={classNames(
                'px-3.5 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition-colors',
                activeOfferTab === tab
                  ? 'bg-brand-500 text-ink-950'
                  : 'bg-ink-800 text-gray-400 hover:text-gray-200 hover:bg-ink-700'
              )}
            >
              {OFFER_TAB_LABELS[tab]}
            </button>
          ))}
        </div>
        {offersLoading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 size={28} className="animate-spin text-brand-500" />
          </div>
        ) : offersError ? (
          <ErrorState message={offersError} onRetry={loadOffers} />
        ) : offersList.length === 0 ? (
          <EmptyState
            title="No offers available right now"
            message="New offers appear here when providers have matching inventory. Check back soon."
            icon={<Filter size={24} />}
          />
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4">
            {offersList.slice(0, 3).map((offer) => (
              <OfferCard key={offer.id} offer={offer} onStart={handleStartOfferClick} />
            ))}
          </div>
        )}
      </div>

      {/* Available ads + tasks */}
      <div className="grid lg:grid-cols-2 gap-4 sm:gap-6 mb-5 sm:mb-6">
        <div className="card p-4 sm:p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-semibold text-gray-300">Available PTC Ads</h3>
            <Link to="/ptc" className="text-xs text-brand-400 hover:text-brand-300">View all</Link>
          </div>
          {ads.length === 0 ? (
            <p className="text-sm text-gray-500 py-6 text-center">No ads available right now</p>
          ) : (
            <div className="space-y-2">
              {ads.map((ad) => (
                <Link key={ad.id} to={`/ptc/${ad.id}`} className="flex items-center justify-between p-3 rounded-lg bg-ink-800 hover:bg-ink-750 transition-colors">
                  <div className="min-w-0">
                    <div className="text-sm text-gray-200 truncate">{ad.title}</div>
                    <div className="text-xs text-gray-500">{ad.advertiser} · {ad.duration_seconds}s</div>
                  </div>
                  <span className="text-sm font-mono font-semibold text-brand-400 shrink-0 ml-2">{formatXc(ad.reward)} XC</span>
                </Link>
              ))}
            </div>
          )}
        </div>

        <div className="card p-4 sm:p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-semibold text-gray-300">Available Tasks</h3>
            <Link to="/tasks" className="text-xs text-brand-400 hover:text-brand-300">View all</Link>
          </div>
          {tasks.length === 0 ? (
            <p className="text-sm text-gray-500 py-6 text-center">No tasks available right now</p>
          ) : (
            <div className="space-y-2">
              {tasks.map((task) => (
                <Link key={task.id} to={`/tasks/${task.id}`} className="flex items-center justify-between p-3 rounded-lg bg-ink-800 hover:bg-ink-750 transition-colors">
                  <div className="min-w-0">
                    <div className="text-sm text-gray-200 truncate">{task.title}</div>
                    <div className="text-xs text-gray-500">{task.category} · {task.task_type.replace('_', ' ')}</div>
                  </div>
                  <span className="text-sm font-mono font-semibold text-brand-400 shrink-0 ml-2">{formatXc(task.reward)} XC</span>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Recent transactions */}
      <div className="card p-4 sm:p-5">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2">
            <Activity size={16} /> Recent Earnings
          </h3>
          <Link to="/transactions" className="text-xs text-brand-400 hover:text-brand-300">View all</Link>
        </div>
        {recentTx.length === 0 ? (
          <p className="text-sm text-gray-500 py-6 text-center">No transactions yet</p>
        ) : (
          <div className="space-y-1">
            {recentTx.map((tx) => (
              <div key={tx.id} className="flex items-center justify-between py-2.5 border-b border-ink-700 last:border-0">
                <div className="flex items-center gap-3 min-w-0">
                  <div className={`w-2 h-2 rounded-full shrink-0 ${tx.amount > 0 ? 'bg-success-500' : 'bg-danger-500'}`} />
                  <div className="min-w-0">
                    <div className="text-sm text-gray-200 truncate">{tx.description}</div>
                    <div className="text-xs text-gray-500">{timeAgo(tx.created_at)}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0 ml-3">
                  {tx.status !== 'completed' && (
                    <Badge variant={tx.status === 'pending' ? 'warning' : 'neutral'}>
                      {tx.status}
                    </Badge>
                  )}
                  <span className={`text-sm font-mono font-semibold ${tx.amount > 0 ? 'text-success-500' : 'text-danger-500'}`}>
                    {tx.amount > 0 ? '+' : ''}{tx.currency === 'XC' ? `${formatXc(tx.amount)} XC` : formatMoney(tx.amount)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <OfferDetailModal
        offer={selectedOffer}
        open={offerModalOpen}
        onClose={() => setOfferModalOpen(false)}
        onConfirm={handleConfirmStartOffer}
        loading={offerStarting}
      />
    </div>
  );
}
