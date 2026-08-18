import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth';
import { listMyReferrals, getSettings, getErrorMessage } from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, StatCard, EmptyState } from '@/components/ui';
import { formatMoney, formatDate } from '@/lib/format';
import { Users, Gift, Copy, Check, DollarSign } from 'lucide-react';
import { useToast } from '@/lib/toast';
import { Link } from '@/lib/router';
import type { ReferralRow, AppSettings } from '@/types';

export function ReferralsPage() {
  const { profile } = useAuth();
  const { toast } = useToast();
  const [referrals, setReferrals] = useState<ReferralRow[]>([]);
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [refs, s] = await Promise.all([listMyReferrals(), getSettings()]);
      setReferrals(refs);
      setSettings(s);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load referrals'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const referralLink = `${window.location.origin}/#/register?ref=${profile?.username ?? ''}`;

  const copyLink = () => {
    navigator.clipboard.writeText(referralLink);
    setCopied(true);
    toast('Referral link copied!', 'success');
    setTimeout(() => setCopied(false), 2000);
  };

  if (loading) return <LoadingScreen label="Loading referrals..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  const totalEarned = referrals.reduce((sum, r) => sum + r.reward_amount, 0);

  return (
    <div>
      <PageHeader title="Referrals" subtitle="Invite friends and earn commission" />

      {/* Referral link card */}
      <div className="card p-4 sm:p-6 mb-5 sm:mb-6 bg-gradient-to-br from-ink-850 to-ink-800">
        <div className="flex items-center gap-2 mb-4">
          <Gift size={18} className="text-brand-400" />
          <h3 className="text-sm font-semibold text-gray-200">Your Referral Link</h3>
        </div>
        <div className="flex flex-col sm:flex-row gap-3 mb-4">
          <div className="flex-1 flex items-center gap-2 px-3.5 py-2.5 rounded-lg bg-ink-900 border border-ink-700 min-w-0">
            <span className="text-sm text-gray-400 truncate flex-1">{referralLink}</span>
          </div>
          <button onClick={copyLink} className="btn-primary shrink-0 w-full sm:w-auto">
            {copied ? <Check size={16} /> : <Copy size={16} />} {copied ? 'Copied' : 'Copy Link'}
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-4">
          Earn <span className="text-brand-400 font-medium">{settings?.referral_commission_percent ?? 0}%</span> of every PTC/task reward and <span className="text-brand-400 font-medium">{settings?.referral_deposit_commission_percent ?? 0}%</span> of every deposit made by people you refer — for as long as they're active.
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-3 sm:gap-4 mb-5 sm:mb-6">
        <StatCard label="Total Referrals" value={referrals.length} icon={<Users size={18} />} accent="brand" />
        <StatCard label="Referral Earnings" value={formatMoney(totalEarned)} icon={<DollarSign size={18} />} accent="brand" />
      </div>

      {/* Referral list */}
      <div className="card p-4 sm:p-5">
        <h3 className="text-sm font-semibold text-gray-300 mb-4">Referral History</h3>
        {referrals.length === 0 ? (
          <EmptyState title="No referrals yet" message="Share your link to start earning from your friends' activity." icon={<Users size={24} />} />
        ) : (
          <>
            {/* Desktop table */}
            <div className="hidden sm:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-gray-500 border-b border-ink-700">
                    <th className="pb-2 px-4 font-medium">Username</th>
                    <th className="pb-2 px-4 font-medium">Email</th>
                    <th className="pb-2 px-4 font-medium">Joined</th>
                    <th className="pb-2 px-4 font-medium text-right">Total Earn</th>
                  </tr>
                </thead>
                <tbody>
                  {referrals.map((r) => (
                    <tr key={r.id} className="border-b border-ink-700 last:border-0">
                      <td className="py-2.5 px-4 text-gray-200 truncate max-w-[140px]">
                        <Link to={`/profile/${r.username}`} className="hover:text-brand-400 transition-colors">{r.username}</Link>
                      </td>
                      <td className="py-2.5 px-4 text-gray-400 truncate max-w-[200px]">{r.email}</td>
                      <td className="py-2.5 px-4 text-gray-400">{formatDate(r.created_at)}</td>
                      <td className="py-2.5 px-4 text-right font-mono font-semibold text-brand-400">
                        {formatMoney(r.reward_amount)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile cards */}
            <div className="sm:hidden space-y-3">
              {referrals.map((r) => (
                <div key={r.id} className="flex items-center justify-between gap-3 py-3 border-b border-ink-700 last:border-0">
                  <div className="min-w-0 flex-1">
                    <Link to={`/profile/${r.username}`} className="text-sm text-gray-200 truncate hover:text-brand-400 transition-colors">{r.username}</Link>
                    <div className="text-xs text-gray-500 truncate">{r.email}</div>
                    <div className="text-xs text-gray-600 mt-0.5">{formatDate(r.created_at)}</div>
                  </div>
                  <span className="text-sm font-mono font-semibold text-brand-400 shrink-0">{formatMoney(r.reward_amount)}</span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
