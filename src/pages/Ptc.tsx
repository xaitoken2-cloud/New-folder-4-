import { useEffect, useState } from 'react';
import { Link } from '@/lib/router';
import { listPtcAds, getMyPtcViews, getSettings, getErrorMessage } from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, EmptyState, Badge } from '@/components/ui';
import { PtcAdCard } from '@/components/PtcAdCard';
import { formatMoney, formatXc } from '@/lib/format';
import { MousePointerClick, Clock, Tag, ExternalLink, CheckCircle2 } from 'lucide-react';
import type { PtcAd, PtcAdView } from '@/types';

export function PtcListPage() {
  const [ads, setAds] = useState<PtcAd[]>([]);
  const [views, setViews] = useState<PtcAdView[]>([]);
  const [multiplier, setMultiplier] = useState(10);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [adList, viewList, settings] = await Promise.all([listPtcAds(), getMyPtcViews(), getSettings()]);
      setAds(adList);
      setViews(viewList);
      setMultiplier(settings.reward_multiplier || 10);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load ads'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  if (loading) return <LoadingScreen label="Loading advertisements..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  const completedToday = new Set(
    views.filter((v) => v.status === 'completed' && v.view_date === new Date().toISOString().slice(0, 10))
      .map((v) => v.ptc_ad_id)
  );

  return (
    <div>
      <PageHeader title="PTC Advertisements" subtitle="View ads and earn rewards — server-verified" />
      {ads.length === 0 ? (
        <EmptyState
          title="No ads available"
          message="Check back later for new earning opportunities."
          icon={<MousePointerClick size={24} />}
        />
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {ads.map((ad) => {
            const done = completedToday.has(ad.id);
            return (
              <Link key={ad.id} to={`/ptc/${ad.id}`}>
                <div className={`card card-hover p-5 h-full ${done ? 'opacity-60' : ''}`}>
                  {ad.image_url ? (
                    <div className="w-full h-28 rounded-lg overflow-hidden bg-ink-800 mb-4">
                      <img src={ad.image_url} alt={ad.title} className="w-full h-full object-cover" />
                    </div>
                  ) : (
                    <div className="w-full h-28 rounded-lg bg-gradient-to-br from-ink-700 to-ink-800 mb-4 flex items-center justify-center">
                      <MousePointerClick size={28} className="text-brand-500/40" />
                    </div>
                  )}
                  <div className="flex items-center gap-2 mb-2">
                    <Badge variant="brand">{ad.category}</Badge>
                    {done && <Badge variant="success"><CheckCircle2 size={11} /> Done</Badge>}
                  </div>
                  <h3 className="text-sm font-semibold text-gray-100 mb-1">{ad.title}</h3>
                  <p className="text-xs text-gray-500 mb-3 line-clamp-2">{ad.description}</p>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3 text-xs text-gray-500">
                      <span className="flex items-center gap-1"><Clock size={12} /> {ad.duration_seconds}s</span>
                      <span className="flex items-center gap-1"><Tag size={12} /> {ad.advertiser}</span>
                    </div>
                    <span className="text-base font-mono font-bold text-brand-400">{formatXc(ad.reward * multiplier)} XC</span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-gray-500 mt-2">
                    <span>Earning Rate</span>
                    <span className="font-mono text-gray-300">
                      {(() => {
                        const xcRate = Number.isFinite(ad.reward) && Number.isFinite(ad.duration_seconds) && ad.duration_seconds > 0
                          ? (ad.reward * multiplier) / ad.duration_seconds
                          : 0;
                        return `${xcRate.toFixed(4)} XC/sec`;
                      })()}
                    </span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function PtcViewPage({ adId }: { adId: string }) {
  const [ad, setAd] = useState<PtcAd | null>(null);
  const [phase, setPhase] = useState<'loading' | 'available' | 'viewing' | 'completed' | 'error'>('loading');
  const [viewId, setViewId] = useState<string | null>(null);
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [remaining, setRemaining] = useState(0);
  const [error, setError] = useState('');
  const [claiming, setClaiming] = useState(false);
  const [reward, setReward] = useState<number | null>(null);
  const [multiplier, setMultiplier] = useState(10);

  useEffect(() => {
    (async () => {
      try {
        const a = await getPtcAd(adId);
        if (!a) {
          setPhase('error');
          setError('Advertisement not found or no longer available.');
          return;
        }
        setAd(a);
        try { const s = await getSettings(); setMultiplier(s.reward_multiplier || 10); } catch {}
        setPhase('available');
      } catch (err) {
        setPhase('error');
        setError(getErrorMessage(err, 'Failed to load advertisement'));
      }
    })();
  }, [adId]);

  // Heartbeat loop — sends periodic heartbeats to the server ONLY when the
  // page is visible and focused. When the user switches tabs, minimizes the
  // browser, or blurs the window, heartbeats stop and the server stops
  // accumulating active_seconds (the elapsed-time cap limits any residual
  // credit). When the user returns, heartbeats resume.
  useEffect(() => {
    if (phase !== 'viewing' || !viewId || !sessionToken) return;

    let cancelled = false;
    let interval: ReturnType<typeof setInterval> | null = null;

    const isTabActive = () =>
      document.visibilityState === 'visible' && document.hasFocus();

    const sendHeartbeat = async () => {
      if (cancelled || !isTabActive()) return;
      try {
        const result = await heartbeatPtcView(viewId, sessionToken);
        if (cancelled) return;
        setRemaining(result.remaining);
        if (result.remaining <= 0 && interval) {
          clearInterval(interval);
          interval = null;
        }
      } catch (err) {
        if (cancelled) return;
        const msg = getErrorMessage(err, 'Heartbeat failed');
        setError(msg);
        setPhase('error');
        if (interval) clearInterval(interval);
      }
    };

    // Send a heartbeat immediately on focus/return to resume quickly
    const handleVisible = () => {
      if (document.visibilityState === 'visible' && !cancelled) {
        sendHeartbeat();
      }
    };

    interval = setInterval(sendHeartbeat, 5000);
    document.addEventListener('visibilitychange', handleVisible);
    window.addEventListener('focus', handleVisible);

    return () => {
      cancelled = true;
      if (interval) clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisible);
      window.removeEventListener('focus', handleVisible);
    };
  }, [phase, viewId, sessionToken]);

  const handleStart = async () => {
    setError('');
    // Open the advertiser destination in a real new browser tab synchronously
    // with the user gesture, so popup blockers don't interfere.
    if (ad?.destination_url) {
      try {
        const url = new URL(ad.destination_url, window.location.origin);
        if (url.protocol === 'http:' || url.protocol === 'https:') {
          window.open(url.href, '_blank', 'noopener,noreferrer');
        }
      } catch {
        // invalid URL — skip opening
      }
    }
    try {
      const result = await startPtcView(adId);
      setViewId(result.view_id);
      setSessionToken(result.session_token);
      setRemaining(result.required_duration);
      setPhase('viewing');
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to start viewing'));
    }
  };

  const handleClaim = async () => {
    if (!viewId) return;
    setClaiming(true);
    setError('');
    try {
      const result = await claimPtcView(viewId);
      if (result.ok) {
        setReward(result.reward ?? ad?.reward ?? 0);
        setPhase('completed');
      } else {
        setError('Claim failed. Please try again.');
      }
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to claim reward'));
    } finally {
      setClaiming(false);
    }
  };

  if (phase === 'loading') return <LoadingScreen label="Loading advertisement..." />;

  if (phase === 'error') {
    return (
      <div>
        <Link to="/ptc" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
          ← Back to PTC Ads
        </Link>
        <ErrorState message={error} />
      </div>
    );
  }

  if (!ad) return null;

  const progress = ad.duration_seconds > 0
    ? Math.min(100, ((ad.duration_seconds - remaining) / ad.duration_seconds) * 100)
    : 0;

  const canClaim = phase === 'viewing' && remaining <= 0;

  return (
    <div className="max-w-2xl mx-auto">
      <Link to="/ptc" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
        ← Back to PTC Ads
      </Link>

      <PtcAdCard
        title={ad.title}
        description={ad.description}
        advertiser={ad.advertiser}
        category={ad.category}
        image_url={ad.image_url}
        reward={ad.reward * multiplier}
        duration_seconds={ad.duration_seconds}
        interactive={phase === 'available'}
        ctaLabel="Start Viewing"
        imageOverlay={
          <>
            {phase === 'viewing' && (
              <div className="absolute top-3 right-3">
                <Badge variant="warning">
                  <span className="w-1.5 h-1.5 rounded-full bg-warning-500 animate-pulse" /> Viewing
                </Badge>
              </div>
            )}
            {phase === 'completed' && (
              <div className="absolute inset-0 bg-ink-950/80 flex items-center justify-center backdrop-blur-sm">
                <div className="text-center">
                  <div className="w-16 h-16 rounded-full bg-success-500/10 flex items-center justify-center mx-auto mb-3 text-success-500">
                    <CheckCircle2 size={32} />
                  </div>
                  <p className="text-sm font-semibold text-gray-100">View Complete!</p>
                  <p className="text-xs text-gray-500 mt-1">Reward: <span className="text-brand-400 font-mono font-semibold">{formatXc(reward ?? 0)} XC</span></p>
                </div>
              </div>
            )}
          </>
        }
      >
        {/* Progress bar during viewing */}
        {phase === 'viewing' && (
          <div className="mb-4">
            <div className="flex items-center justify-between text-xs text-gray-500 mb-2">
              <span>Time remaining</span>
              <span className="font-mono text-brand-400">{remaining}s</span>
            </div>
            <div className="h-2 rounded-full bg-ink-700 overflow-hidden">
              <div
                className="h-full brand-gradient transition-all duration-300 rounded-full"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>
        )}

        {error && (
          <div className="px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm mb-4">
            {error}
          </div>
        )}

        {/* Action buttons */}
        {phase === 'available' && (
          <button onClick={handleStart} className="btn-primary w-full">
            <MousePointerClick size={18} /> Start Viewing
          </button>
        )}
        {phase === 'viewing' && (
          <div className="space-y-2">
            {ad.destination_url && (
              <a
                href={ad.destination_url}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secondary w-full"
              >
                <ExternalLink size={16} /> Open Advertiser in New Tab
              </a>
            )}
            <button
              onClick={handleClaim}
              disabled={!canClaim || claiming}
              className="btn-primary w-full"
            >
              {claiming ? 'Verifying...' : canClaim ? 'Claim Reward' : `Wait ${remaining}s`}
            </button>
            <p className="text-xs text-gray-500 text-center">
              Reward is verified server-side. Stay on this page until the timer completes.
            </p>
          </div>
        )}
        {phase === 'completed' && (
          <div className="space-y-2">
            <div className="px-4 py-3 rounded-lg bg-success-500/10 border border-success-500/20 text-success-500 text-sm text-center">
              You earned {formatXc(reward ?? 0)} XC for viewing this ad.
            </div>
            <Link to="/ptc" className="btn-secondary w-full">Back to Ads</Link>
          </div>
        )}
      </PtcAdCard>
    </div>
  );
}

// Import at bottom to avoid circular issues
import { getPtcAd, startPtcView, claimPtcView, heartbeatPtcView } from '@/lib/api';
