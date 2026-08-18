import { useEffect, useState } from 'react';
import { Link } from '@/lib/router';
import { useAuth } from '@/lib/auth';
import { useToast } from '@/lib/toast';
import { listTransactions, listMyDeposits, listMyWithdrawals, createDeposit, requestWithdrawal, xcLookupRecipient, xcTransfer, listXcTransfers, getDashboard, getErrorMessage } from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, StatCard, EmptyState, Badge, TableSkeleton, Modal, Spinner } from '@/components/ui';
import { formatMoney, formatXc, formatDateTime } from '@/lib/format';
import {
  ArrowDownToLine, ArrowUpFromLine, ArrowRightFromLine, DollarSign,
  ScrollText, Coins, Send, Search, ArrowRight, Check, AlertCircle,
} from 'lucide-react';
import type { Transaction, Deposit, Withdrawal, TransactionCurrency, XcRecipientLookup } from '@/types';

interface UnifiedTx {
  id: string;
  description: string;
  amount: number;
  currency: 'USD' | 'XC';
  status: string;
  created_at: string;
  direction: 'in' | 'out';
}

function CurrencyBadge({ currency }: { currency: TransactionCurrency }) {
  return (
    <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold ${
      currency === 'XC' ? 'bg-brand-500/15 text-brand-400' : 'bg-ink-700 text-gray-400'
    }`}>
      {currency}
    </span>
  );
}

function SendXcPanel({
  xcBalance,
  onTransferred,
}: {
  xcBalance: number;
  onTransferred: () => void;
}) {
  const { toast } = useToast();
  const [step, setStep] = useState<'form' | 'confirm'>('form');
  const [query, setQuery] = useState('');
  const [recipient, setRecipient] = useState<XcRecipientLookup | null>(null);
  const [amount, setAmount] = useState('');
  const [searching, setSearching] = useState(false);
  const [sending, setSending] = useState(false);
  const [clientRef, setClientRef] = useState('');

  const resetForm = () => {
    setStep('form');
    setQuery('');
    setRecipient(null);
    setAmount('');
    setClientRef('');
  };

  const handleSearch = async () => {
    if (!query.trim()) {
      toast('Please enter a username or email', 'error');
      return;
    }
    setSearching(true);
    setRecipient(null);
    try {
      const result = await xcLookupRecipient(query.trim());
      if (!result.found) {
        toast('User not found.', 'error');
        return;
      }
      setRecipient(result);
      setQuery('');
    } catch (err) {
      toast(getErrorMessage(err, 'Lookup failed'), 'error');
    } finally {
      setSearching(false);
    }
  };

  const handleProceedToConfirm = () => {
    if (!recipient || !recipient.found) {
      toast('Please select a recipient first', 'error');
      return;
    }
    const amt = parseFloat(amount);
    if (isNaN(amt) || amt <= 0) {
      toast('Please enter a valid amount', 'error');
      return;
    }
    if (amt < 0.01) {
      toast('Minimum transfer is 0.01 XC', 'error');
      return;
    }
    if (amt > xcBalance) {
      toast('Insufficient XC balance', 'error');
      return;
    }
    setClientRef(`${Date.now()}-${Math.random().toString(36).slice(2, 10)}`);
    setStep('confirm');
  };

  const handleConfirmTransfer = async () => {
    if (!recipient || !recipient.found) return;
    const amt = parseFloat(amount);
    setSending(true);
    try {
      const result = await xcTransfer(recipient.username!, amt, clientRef);
      if (result.duplicate) {
        toast('Duplicate transfer prevented — the same transfer was already processed.', 'info');
      } else {
        toast(`${formatXc(amt)} XC sent successfully to @${result.recipient_username}.`, 'success');
      }
      resetForm();
      onTransferred();
    } catch (err) {
      toast(getErrorMessage(err, 'Transfer failed'), 'error');
      setStep('form');
    } finally {
      setSending(false);
    }
  };

  const amt = parseFloat(amount) || 0;
  const remaining = xcBalance - amt;

  if (step === 'confirm' && recipient) {
    return (
      <div className="space-y-4">
        <div className="flex items-center gap-2 mb-1">
          <Send size={16} className="text-brand-400" />
          <h3 className="text-sm font-semibold text-gray-200">Confirm Transfer</h3>
        </div>
        <div className="card p-4 border border-ink-700 space-y-2.5">
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">Recipient</span>
            <span className="font-medium text-gray-200">@{recipient.username}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">Amount</span>
            <span className="font-mono font-semibold text-brand-400">{formatXc(amt)} XC</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">Transfer fee</span>
            <span className="font-mono text-gray-400">0 XC</span>
          </div>
          <div className="flex justify-between text-sm border-t border-ink-700 pt-2.5">
            <span className="text-gray-500">Total</span>
            <span className="font-mono font-bold text-gray-200">{formatXc(amt)} XC</span>
          </div>
          <div className="flex justify-between text-sm border-t border-ink-700 pt-2.5">
            <span className="text-gray-500">Remaining balance</span>
            <span className="font-mono font-bold text-brand-400">{formatXc(remaining)} XC</span>
          </div>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setStep('form')} className="btn-secondary flex-1" disabled={sending}>
            Cancel
          </button>
          <button onClick={handleConfirmTransfer} disabled={sending} className="btn-primary flex-1">
            {sending ? <Spinner size={16} /> : 'Confirm Transfer'}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 mb-1">
        <Send size={16} className="text-brand-400" />
        <h3 className="text-sm font-semibold text-gray-200">Send XC</h3>
      </div>
      <p className="text-xs text-gray-500">
        Transfer XC tokens to another GoldClicks user by username or email. USD balance is not affected.
      </p>
      <div className="p-3 rounded-lg bg-ink-800 text-sm text-gray-400">
        Your XC Balance: <span className="font-mono font-semibold text-brand-400">{formatXc(xcBalance)} XC</span>
      </div>

      {recipient && recipient.found ? (
        <div className="p-3 rounded-lg bg-brand-500/10 border border-brand-500/20 flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-brand-500/20 flex items-center justify-center text-brand-400 font-bold text-sm shrink-0">
            {recipient.avatar_url ? (
              <img src={recipient.avatar_url} alt="" className="w-10 h-10 rounded-full object-cover" />
            ) : (
              recipient.username?.charAt(0).toUpperCase() ?? '?'
            )}
          </div>
          <div className="min-w-0 flex-1">
            <Link to={`/profile/${recipient.username}`} className="text-sm font-medium text-gray-200 hover:text-brand-400 transition-colors">@{recipient.username}</Link>
            {recipient.full_name && <div className="text-xs text-gray-500 truncate">{recipient.full_name}</div>}
          </div>
          <button onClick={() => setRecipient(null)} className="text-gray-500 hover:text-danger-500 shrink-0">
            <AlertCircle size={16} />
          </button>
        </div>
      ) : (
        <div>
          <label className="label">Recipient username or email</label>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), handleSearch())}
                placeholder="username or email"
                className="input pl-10"
              />
            </div>
            <button onClick={handleSearch} disabled={searching} className="btn-secondary">
              {searching ? <Spinner size={16} /> : 'Search'}
            </button>
          </div>
        </div>
      )}

      {recipient && recipient.found && (
        <>
          <div>
            <label className="label">Amount (XC)</label>
            <input
              type="number"
              step="0.01"
              min="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              className="input"
            />
          </div>
          <button onClick={handleProceedToConfirm} className="btn-primary w-full">
            Review Transfer
          </button>
        </>
      )}
    </div>
  );
}

export function WalletPage() {
  const { profile, refreshProfile } = useAuth();
  const { toast } = useToast();
  const [unifiedTxs, setUnifiedTxs] = useState<UnifiedTx[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showSendXc, setShowSendXc] = useState(false);
  const [xcTotalSent, setXcTotalSent] = useState(0);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [xcRes, depRes, wdRes, dash] = await Promise.all([
        listXcTransfers(50, 0),
        listTransactions('deposits', 1, 50),
        listTransactions('withdrawals', 1, 50),
        getDashboard(),
      ]);
      setXcTotalSent(dash.xc_total_sent ?? 0);
      const xcRows: UnifiedTx[] = xcRes.map((t) => ({
        id: t.id,
        description: `${t.direction === 'sent' ? 'To' : 'From'} @${t.direction === 'sent' ? t.recipient_username : t.sender_username}`,
        amount: t.amount,
        currency: 'XC',
        status: t.status,
        created_at: t.created_at,
        direction: t.direction === 'sent' ? 'out' : 'in',
      }));
      const depRows: UnifiedTx[] = depRes.data.map((tx) => ({
        id: tx.id,
        description: tx.description,
        amount: tx.amount,
        currency: 'USD',
        status: tx.status,
        created_at: tx.created_at,
        direction: tx.amount > 0 ? 'in' : 'out',
      }));
      const wdRows: UnifiedTx[] = wdRes.data.map((tx) => ({
        id: tx.id,
        description: tx.description,
        amount: tx.amount,
        currency: 'USD',
        status: tx.status,
        created_at: tx.created_at,
        direction: tx.amount > 0 ? 'in' : 'out',
      }));
      const merged = [...xcRows, ...depRows, ...wdRows].sort(
        (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
      );
      setUnifiedTxs(merged);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load transaction history'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleTransferred = () => {
    refreshProfile();
    load();
  };

  if (loading) return <LoadingScreen label="Loading wallet..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Wallet"
        subtitle="Your balance and financial overview"
        action={
          <div className="flex gap-2 flex-wrap">
            <button onClick={() => setShowSendXc(!showSendXc)} className="btn-primary text-sm">
              <Send size={16} /> <span className="hidden xs:inline sm:inline">Send XC</span>
            </button>
            <Link to="/deposits" className="btn-secondary text-sm">
              <ArrowDownToLine size={16} /> <span className="hidden xs:inline sm:inline">Deposit</span>
            </Link>
            <Link to="/withdrawals" className="btn-secondary text-sm">
              <ArrowUpFromLine size={16} /> <span className="hidden xs:inline sm:inline">Withdraw</span>
            </Link>
          </div>
        }
      />

      {showSendXc && (
        <div className="card p-4 sm:p-5 mb-5 sm:mb-6 animate-slide-up">
          <SendXcPanel xcBalance={profile?.xc_balance ?? 0} onTransferred={handleTransferred} />
        </div>
      )}

      <div className="grid grid-cols-2 gap-3 sm:gap-4 mb-5 sm:mb-6">
        <StatCard label="XC Balance" value={`${formatXc(profile?.xc_balance ?? 0)} XC`} icon={<Coins size={18} />} accent="brand" />
        <StatCard label="USD Balance" value={formatMoney(profile?.available_balance ?? 0)} icon={<DollarSign size={18} />} accent="brand" />
      </div>

      <div className="grid grid-cols-3 gap-3 sm:gap-4 mb-5 sm:mb-6">
        <StatCard label="Total Deposit" value={formatMoney(profile?.total_deposited ?? 0)} icon={<ArrowDownToLine size={18} />} accent="purple" />
        <StatCard label="Total Withdrawn" value={formatMoney(profile?.total_withdrawn ?? 0)} icon={<ArrowUpFromLine size={18} />} accent="purple" />
        <StatCard label="Total XC Sent" value={`${formatXc(xcTotalSent)} XC`} icon={<ArrowRightFromLine size={18} />} accent="purple" />
      </div>

      <div className="card p-4 sm:p-5 mb-5 sm:mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2">
            <ScrollText size={16} /> Transaction History
          </h3>
          <Link to="/transactions" className="text-xs text-brand-400 hover:text-brand-300">View all</Link>
        </div>
        {unifiedTxs.length === 0 ? (
          <EmptyState title="No transactions yet" message="Your XC transfers, deposits, and withdrawals will appear here." />
        ) : (
          <div className="space-y-1">
            {unifiedTxs.map((tx) => (
              <div key={tx.id} className="flex items-center justify-between py-2.5 border-b border-ink-700 last:border-0">
                <div className="flex items-center gap-3 min-w-0">
                  <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${tx.direction === 'in' ? 'bg-success-500/10 text-success-500' : 'bg-danger-500/10 text-danger-500'}`}>
                    {tx.direction === 'in' ? <ArrowDownToLine size={14} /> : <ArrowUpFromLine size={14} />}
                  </div>
                  <div className="min-w-0">
                    <div className="text-sm text-gray-200 truncate">{tx.description}</div>
                    <div className="text-xs text-gray-500 flex items-center gap-2">
                      {formatDateTime(tx.created_at)}
                      <CurrencyBadge currency={tx.currency} />
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0 ml-3">
                  {tx.status !== 'completed' && (
                    <Badge variant={tx.status === 'pending' ? 'warning' : 'neutral'}>
                      {tx.status}
                    </Badge>
                  )}
                  <span className={`text-sm font-mono font-semibold ${tx.direction === 'in' ? 'text-success-500' : 'text-danger-500'}`}>
                    {tx.direction === 'in' ? '+' : '-'}{tx.currency === 'XC' ? `${formatXc(tx.amount)} XC` : formatMoney(tx.amount)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export function TransactionsPage() {
  const [txs, setTxs] = useState<Transaction[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [filter, setFilter] = useState<string | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const perPage = 20;

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const result = await listTransactions(filter, page, perPage);
      setTxs(result.data);
      setTotal(result.total);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load transactions'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [page, filter]);

  const filters = [
    { label: 'All', value: undefined },
    { label: 'Earnings', value: 'earnings' },
    { label: 'PTC', value: 'ptc' },
    { label: 'Tasks', value: 'tasks' },
    { label: 'Referrals', value: 'referrals' },
    { label: 'Deposits', value: 'deposits' },
    { label: 'Withdrawals', value: 'withdrawals' },
  ];

  const totalPages = Math.ceil(total / perPage);

  return (
    <div>
      <PageHeader title="History" subtitle="Your complete financial history" />

      <div className="flex flex-wrap gap-2 mb-4">
        {filters.map((f) => (
          <button
            key={f.label}
            onClick={() => { setFilter(f.value); setPage(1); }}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
              filter === f.value ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400 hover:bg-ink-700'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {loading ? (
        <TableSkeleton />
      ) : error ? (
        <ErrorState message={error} onRetry={load} />
      ) : txs.length === 0 ? (
        <EmptyState title="No transactions found" message="Try a different filter or check back later." />
      ) : (
        <>
          {/* Desktop table */}
          <div className="card overflow-hidden hidden sm:block">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-ink-800">
                  <tr>
                    <th className="table-header">Description</th>
                    <th className="table-header">Type</th>
                    <th className="table-header">Currency</th>
                    <th className="table-header">Status</th>
                    <th className="table-header">Date</th>
                    <th className="table-header text-right">Amount</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-ink-700">
                  {txs.map((tx) => (
                    <tr key={tx.id} className="hover:bg-ink-800/50">
                      <td className="table-cell">{tx.description}</td>
                      <td className="table-cell">
                        <Badge variant="neutral">{tx.type.replace('_', ' ')}</Badge>
                      </td>
                      <td className="table-cell">
                        <CurrencyBadge currency={tx.currency ?? 'USD'} />
                      </td>
                      <td className="table-cell">
                        <Badge variant={tx.status === 'completed' ? 'success' : tx.status === 'pending' ? 'warning' : tx.status === 'reversed' ? 'danger' : 'neutral'}>
                          {tx.status}
                        </Badge>
                      </td>
                      <td className="table-cell text-gray-500">{formatDateTime(tx.created_at)}</td>
                      <td className={`table-cell text-right font-mono font-semibold ${tx.amount > 0 ? 'text-success-500' : 'text-danger-500'}`}>
                        {tx.amount > 0 ? '+' : ''}{tx.currency === 'XC' ? `${formatXc(tx.amount)} XC` : formatMoney(tx.amount)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Mobile cards */}
          <div className="sm:hidden space-y-3">
            {txs.map((tx) => (
              <div key={tx.id} className="card p-4">
                <div className="flex items-start justify-between gap-2 mb-2">
                  <div className="min-w-0 flex-1">
                    <div className="text-sm text-gray-200 truncate">{tx.description}</div>
                    <div className="text-xs text-gray-500 mt-0.5 flex items-center gap-2">
                      {formatDateTime(tx.created_at)}
                      <CurrencyBadge currency={tx.currency ?? 'USD'} />
                    </div>
                  </div>
                  <span className={`text-sm font-mono font-semibold shrink-0 ${tx.amount > 0 ? 'text-success-500' : 'text-danger-500'}`}>
                    {tx.amount > 0 ? '+' : ''}{tx.currency === 'XC' ? `${formatXc(tx.amount)} XC` : formatMoney(tx.amount)}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant="neutral">{tx.type.replace('_', ' ')}</Badge>
                  <Badge variant={tx.status === 'completed' ? 'success' : tx.status === 'pending' ? 'warning' : tx.status === 'reversed' ? 'danger' : 'neutral'}>
                    {tx.status}
                  </Badge>
                </div>
              </div>
            ))}
          </div>
          {totalPages > 1 && (
            <div className="flex items-center justify-between mt-4">
              <span className="text-xs text-gray-500">Page {page} of {totalPages} · {total} total</span>
              <div className="flex gap-2">
                <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page <= 1} className="btn-secondary text-xs px-3 py-1.5">
                  Previous
                </button>
                <button onClick={() => setPage(Math.min(totalPages, page + 1))} disabled={page >= totalPages} className="btn-secondary text-xs px-3 py-1.5">
                  Next
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

export function DepositsPage() {
  const { toast } = useToast();
  const [deposits, setDeposits] = useState<Deposit[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(true);
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState('manual');
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const list = await listMyDeposits();
      setDeposits(list);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load deposits'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) {
      toast('Please enter a valid amount', 'error');
      return;
    }
    setSubmitting(true);
    try {
      await createDeposit(amt, method);
      toast('Deposit request created! Awaiting approval.', 'success');
      setAmount('');
      setShowForm(false);
      load();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to create deposit'), 'error');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) return <LoadingScreen label="Loading deposits..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Deposits"
        subtitle="Add funds to your account"
      />

      {showForm && (
        <div className="card p-4 sm:p-5 mb-5 sm:mb-6 animate-slide-up">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Amount (USD)</label>
              <input type="number" step="0.01" min="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="10.00" className="input" />
            </div>
            <div>
              <label className="label">Payment Method</label>
              <select value={method} onChange={(e) => setMethod(e.target.value)} className="input">
                <option value="manual">Manual Transfer</option>
                <option value="bank">Bank Transfer</option>
                <option value="crypto">Cryptocurrency</option>
              </select>
            </div>
            <div className="flex gap-2">
              <button type="submit" disabled={submitting} className="btn-primary flex-1">
                {submitting ? 'Creating...' : 'Create Deposit Request'}
              </button>
              <button type="button" onClick={() => setShowForm(false)} className="btn-secondary">
                Cancel
              </button>
            </div>
            <p className="text-xs text-gray-500">
              Your deposit will be pending until an admin confirms receipt. Pending deposits do not increase your available balance.
            </p>
          </form>
        </div>
      )}

      {deposits.length === 0 ? (
        <EmptyState title="No deposits yet" message="Create a deposit request to add funds to your account." icon={<DollarSign size={24} />} />
      ) : (
        <>
          <h2 className="text-lg font-semibold text-gray-100 mb-3">Deposit History</h2>
          {/* Desktop table */}
          <div className="card overflow-hidden hidden sm:block">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-ink-800">
                  <tr>
                    <th className="table-header">Amount</th>
                    <th className="table-header">Method</th>
                    <th className="table-header">Status</th>
                    <th className="table-header">Date</th>
                    <th className="table-header">Note</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-ink-700">
                  {deposits.map((d) => (
                    <tr key={d.id} className="hover:bg-ink-800/50">
                      <td className="table-cell font-mono font-semibold text-brand-400">{formatMoney(d.amount)}</td>
                      <td className="table-cell">{d.payment_method}</td>
                      <td className="table-cell">
                        <Badge variant={d.status === 'approved' ? 'success' : d.status === 'pending' ? 'warning' : d.status === 'rejected' ? 'danger' : 'neutral'}>
                          {d.status}
                        </Badge>
                      </td>
                      <td className="table-cell text-gray-500">{formatDateTime(d.created_at)}</td>
                      <td className="table-cell text-gray-500">{d.admin_note || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Mobile cards */}
          <div className="sm:hidden space-y-3">
            {deposits.map((d) => (
              <div key={d.id} className="card p-4">
                <div className="flex items-start justify-between gap-2 mb-2">
                  <span className="text-sm font-mono font-semibold text-brand-400">{formatMoney(d.amount)}</span>
                  <Badge variant={d.status === 'approved' ? 'success' : d.status === 'pending' ? 'warning' : d.status === 'rejected' ? 'danger' : 'neutral'}>
                    {d.status}
                  </Badge>
                </div>
                <div className="flex items-center justify-between text-xs">
                  <span className="text-gray-400 capitalize">{d.payment_method}</span>
                  <span className="text-gray-500">{formatDateTime(d.created_at)}</span>
                </div>
                {d.admin_note && <div className="text-xs text-gray-500 mt-2 break-words">{d.admin_note}</div>}
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

export function WithdrawalsPage() {
  const { profile, refreshProfile } = useAuth();
  const { toast } = useToast();
  const [withdrawals, setWithdrawals] = useState<Withdrawal[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(true);
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState('manual');
  const [destination, setDestination] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const list = await listMyWithdrawals();
      setWithdrawals(list);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load withdrawals'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) return;
    setSubmitting(true);
    try {
      await requestWithdrawal(amt, method, destination);
      toast('Withdrawal request created! Awaiting approval.', 'success');
      setShowForm(false);
      setAmount('');
      setDestination('');
      refreshProfile();
      load();
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to create withdrawal'));
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) return <LoadingScreen label="Loading withdrawals..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Withdrawals"
        subtitle="Withdraw your earnings"
      />

      {showForm && (
        <div className="card p-4 sm:p-5 mb-5 sm:mb-6 animate-slide-up">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="p-3 rounded-lg bg-ink-800 text-sm text-gray-400">
              Available balance: <span className="font-mono font-semibold text-brand-400">{formatMoney(profile?.available_balance ?? 0)}</span>
            </div>
            <div>
              <label className="label">Amount (USD)</label>
              <input type="number" step="0.01" min="1" required value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="10.00" className="input" />
            </div>
            <div>
              <label className="label">Withdrawal Method</label>
              <select value={method} onChange={(e) => setMethod(e.target.value)} className="input">
                <option value="manual">Manual Transfer</option>
                <option value="bank">Bank Transfer</option>
                <option value="crypto">Cryptocurrency</option>
                <option value="paypal">PayPal</option>
              </select>
            </div>
            <div>
              <label className="label">Destination / Account</label>
              <input required value={destination} onChange={(e) => setDestination(e.target.value)} placeholder="Account number, email, or wallet address" className="input" />
            </div>
            {error && <div className="px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm">{error}</div>}
            <div className="flex gap-2">
              <button type="submit" disabled={submitting} className="btn-primary flex-1">
                {submitting ? 'Processing...' : 'Request Withdrawal'}
              </button>
              <button type="button" onClick={() => setShowForm(false)} className="btn-secondary">
                Cancel
              </button>
            </div>
            <p className="text-xs text-gray-500">
              Funds will be reserved immediately. Withdrawals are processed after admin approval. If rejected, funds are returned to your balance.
            </p>
          </form>
        </div>
      )}

      {withdrawals.length === 0 ? (
        <EmptyState title="No withdrawals yet" message="Request a withdrawal to cash out your earnings." icon={<ArrowUpFromLine size={24} />} />
      ) : (
        <>
          <h2 className="text-lg font-semibold text-gray-100 mb-3">Withdrawal History</h2>
          {/* Desktop table */}
          <div className="card overflow-hidden hidden sm:block">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-ink-800">
                  <tr>
                    <th className="table-header">Amount</th>
                    <th className="table-header">Method</th>
                    <th className="table-header">Destination</th>
                    <th className="table-header">Status</th>
                    <th className="table-header">Date</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-ink-700">
                  {withdrawals.map((w) => (
                    <tr key={w.id} className="hover:bg-ink-800/50">
                      <td className="table-cell font-mono font-semibold text-brand-400">{formatMoney(w.amount)}</td>
                      <td className="table-cell">{w.withdrawal_method}</td>
                      <td className="table-cell text-gray-500 truncate max-w-[180px]">{w.destination}</td>
                      <td className="table-cell">
                        <Badge variant={w.status === 'paid' ? 'success' : w.status === 'pending' ? 'warning' : w.status === 'rejected' ? 'danger' : 'neutral'}>
                          {w.status}
                        </Badge>
                      </td>
                      <td className="table-cell text-gray-500">{formatDateTime(w.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Mobile cards */}
          <div className="sm:hidden space-y-3">
            {withdrawals.map((w) => (
              <div key={w.id} className="card p-4">
                <div className="flex items-start justify-between gap-2 mb-2">
                  <span className="text-sm font-mono font-semibold text-brand-400">{formatMoney(w.amount)}</span>
                  <Badge variant={w.status === 'paid' ? 'success' : w.status === 'pending' ? 'warning' : w.status === 'rejected' ? 'danger' : 'neutral'}>
                    {w.status}
                  </Badge>
                </div>
                <div className="flex items-center justify-between text-xs mb-1">
                  <span className="text-gray-400 capitalize">{w.withdrawal_method}</span>
                  <span className="text-gray-500">{formatDateTime(w.created_at)}</span>
                </div>
                <div className="text-xs text-gray-500 break-all">{w.destination}</div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
