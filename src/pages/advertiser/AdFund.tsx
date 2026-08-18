import { useState } from 'react';
import { Link } from '@/lib/router';
import { useAuth } from '@/lib/auth';
import { useToast } from '@/lib/toast';
import { adTransferToAdvertising, getErrorMessage } from '@/lib/api';
import { PageHeader, Spinner } from '@/components/ui';
import { formatMoney } from '@/lib/format';
import { Wallet } from 'lucide-react';

export function AdFundPage() {
  const { profile, refreshProfile } = useAuth();
  const { toast } = useToast();
  const [amount, setAmount] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) {
      toast('Enter a valid amount', 'error');
      return;
    }
    if (profile && amt > profile.available_balance) {
      toast('Insufficient available balance', 'error');
      return;
    }
    setSubmitting(true);
    try {
      const result = await adTransferToAdvertising(amt);
      await refreshProfile();
      toast(`Transferred ${formatMoney(amt)} to advertising balance`, 'success');
      setAmount('');
      if (result.advertising_balance !== undefined) {
        toast(`New advertising balance: ${formatMoney(result.advertising_balance)}`, 'success');
      }
    } catch (err) {
      toast(getErrorMessage(err, 'Transfer failed'), 'error');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="max-w-lg mx-auto">
      <Link to="/advertiser" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
        ← Back to Advertiser Dashboard
      </Link>

      <PageHeader title="Fund Advertising Balance" subtitle="Transfer from your available main USD balance" />

      <div className="card p-6">
        {/* Balance display */}
        <div className="grid grid-cols-2 gap-4 mb-6">
          <div className="p-4 rounded-lg bg-ink-800">
            <div className="text-xs text-gray-500 mb-1">Available Balance</div>
            <div className="text-lg font-mono font-bold text-gray-100">{formatMoney(profile?.available_balance ?? 0)}</div>
          </div>
          <div className="p-4 rounded-lg bg-ink-800">
            <div className="text-xs text-gray-500 mb-1">Advertising Balance</div>
            <div className="text-lg font-mono font-bold text-brand-400">{formatMoney(profile?.advertising_balance ?? 0)}</div>
          </div>
        </div>

        {/* Transfer form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="label">Amount to Transfer</label>
            <input
              type="number"
              step="0.01"
              min="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              className="input"
              disabled={submitting}
            />
            <p className="text-xs text-gray-500 mt-3">
              This moves funds from your main USD balance to your advertising Balance. You can transfer back by stopping a campaign — unspent budget is refunded.
            </p>
          </div>

          <button type="submit" disabled={submitting} className="btn-primary w-full">
            {submitting ? <Spinner size={18} /> : <><Wallet size={18} /> Transfer Funds</>}
          </button>
        </form>
      </div>
    </div>
  );
}
