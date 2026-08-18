import { useState, useEffect, useCallback } from 'react';
import {
  Gift, Clock, Star, Smartphone, Globe, Apple,
  ExternalLink, AlertCircle, Loader2, Filter,
} from 'lucide-react';
import type { Offer, OfferType, OfferPlatform } from '@/types';
import { offerListAvailable, offerStartSession, getErrorMessage } from '@/lib/api';
import { formatMoney, formatXc } from '@/lib/format';
import { useToast } from '@/lib/toast';
import { PageHeader, EmptyState, ErrorState, Modal, Badge } from '@/components/ui';
import { classNames } from '@/lib/format';

type Tab = 'all' | 'survey' | 'app_install' | 'game';

const TAB_LABELS: Record<Tab, string> = {
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

export function OffersPage() {
  const { toast } = useToast();
  const [activeTab, setActiveTab] = useState<Tab>('all');
  const [offers, setOffers] = useState<Offer[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedOffer, setSelectedOffer] = useState<Offer | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [starting, setStarting] = useState(false);

  const loadOffers = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await offerListAvailable(activeTab, 'all');
      setOffers(data);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load offers'));
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => {
    loadOffers();
  }, [loadOffers]);

  const handleStartClick = (offer: Offer) => {
    setSelectedOffer(offer);
    setModalOpen(true);
  };

  const handleConfirmStart = async () => {
    if (!selectedOffer) return;
    setStarting(true);
    try {
      const result = await offerStartSession(selectedOffer.id);
      if (result.error) {
        toast(result.error, 'error');
        return;
      }
      setModalOpen(false);
      toast('Opening offer... You will be credited after the provider confirms completion.', 'success');
      if (result.tracking_url) {
        window.open(result.tracking_url, '_blank', 'noopener,noreferrer');
      }
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to start offer'), 'error');
    } finally {
      setStarting(false);
    }
  };

  return (
    <div>
      <PageHeader
        title="Offers"
        subtitle="Complete surveys, install apps, play games and complete offers to earn rewards."
      />

      {/* Hero banner */}
      <div className="card p-5 sm:p-6 mb-5 bg-gradient-to-br from-brand-500/10 to-ink-850 border-brand-500/20">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-brand-500/20 flex items-center justify-center">
            <Gift size={20} className="text-brand-400" />
          </div>
          <div>
            <h2 className="text-base font-bold text-gray-100">Earn More</h2>
            <p className="text-xs text-gray-500">Complete offers from our partners to earn rewards</p>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-1.5 mb-5 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
        {(Object.keys(TAB_LABELS) as Tab[]).map((tab) => (
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

      {/* Content */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 size={28} className="animate-spin text-brand-500" />
        </div>
      ) : error ? (
        <ErrorState message={error} onRetry={loadOffers} />
      ) : offers.length === 0 ? (
        <EmptyState
          title="No offers available right now"
          message="New offers appear here when providers have matching inventory. Check back soon."
          icon={<Filter size={24} />}
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4">
          {offers.map((offer) => (
            <OfferCard key={offer.id} offer={offer} onStart={handleStartClick} />
          ))}
        </div>
      )}

      <OfferDetailModal
        offer={selectedOffer}
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        onConfirm={handleConfirmStart}
        loading={starting}
      />
    </div>
  );
}
