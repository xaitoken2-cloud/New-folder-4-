import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import {
  adminListUsers, adminSetUserStatus, adminListDeposits, adminApproveDeposit,
  adminRejectDeposit, adminListWithdrawals, adminApproveWithdrawal, adminRejectWithdrawal,
  adminListTransactions, adminListReferrals, adminListTickets, adminReplyTicket,
  adminSetTicketStatus, adminListAuditLogs, adminListPendingTasks, adminReviewTask,
  adminCreatePtcAd, adminUpdatePtcAd, adminDeletePtcAd, adminCreateTask,
  adminUpdateTask, adminDeleteTask, adminUpdateSettings, getSettings,
  adminListPendingCampaigns, adminApproveCampaign, adminRejectCampaign,
  adminSetUserRole, adminAdjustUserBalance, adminListAdvertisers,
  adminListAllCampaigns, adminPauseCampaign, adminResumeCampaign, adminStopCampaign,
  adminImpersonateUser, adminListXcTransfers, adminUpdateUserCountry,
  adminListUndetectedUsers, adminBulkSetCountry,
  getErrorMessage,
} from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { useRouter } from '@/lib/router';
import { useToast } from '@/lib/toast';
import {
  LoadingScreen, ErrorState, PageHeader, EmptyState, Badge,
  Modal, Spinner, ConfirmDialog,
} from '@/components/ui';
import { formatMoney, formatXc, formatDateTime, formatDate } from '@/lib/format';
import { COUNTRY_LIST, COUNTRY_NAME_MAP } from '@/lib/countries';
import {
  Users, MousePointerClick, ListChecks, ArrowDownToLine, ArrowUpFromLine,
  ScrollText, Ticket, FileText, Settings, Search, Check, X, Plus, Pencil, Trash2,
  Megaphone, ExternalLink, Pause, Play, Square, DollarSign,
  LogIn, Coins, Minus, MapPin,
} from 'lucide-react';
import type {
  AdminUserRow, AdminDepositRow, AdminWithdrawalRow, AdminTransactionRow,
  AdminReferralRow, AdminTicketRow, AuditLog, TaskCompletion, PtcAd, Task,
  AppSettings, AdminPendingCampaignsResult, AdminAdvertiserRow,
  AdminAllCampaignsResult, AdminAllPtcCampaign, AdminAllTaskCampaign,
  CampaignStatus,
} from '@/types';

/* ---------- Admin Users ---------- */

export function AdminUsersPage() {
  const [users, setUsers] = useState<AdminUserRow[]>([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [statusTarget, setStatusTarget] = useState<{ id: string; status: string } | null>(null);
  const [roleTarget, setRoleTarget] = useState<{ id: string; role: string } | null>(null);
  const [balanceTarget, setBalanceTarget] = useState<AdminUserRow | null>(null);
  const [adjustCurrency, setAdjustCurrency] = useState<'USDT' | 'XC'>('USDT');
  const [adjustAction, setAdjustAction] = useState<'ADD' | 'SUBTRACT'>('ADD');
  const [adjustAmount, setAdjustAmount] = useState('');
  const [adjustReason, setAdjustReason] = useState('');
  const [adjustStep, setAdjustStep] = useState<'form' | 'confirm'>('form');
  const [adjustSubmitting, setAdjustSubmitting] = useState(false);
  const [impersonating, setImpersonating] = useState(false);
  const [countryTarget, setCountryTarget] = useState<{ id: string; country: string } | null>(null);
  const [countrySaving, setCountrySaving] = useState(false);
  const [undetected, setUndetected] = useState<Array<{ id: string; username: string; email: string | null; created_at: string }>>([]);
  const [undetectedLoading, setUndetectedLoading] = useState(true);
  const [bulkCountry, setBulkCountry] = useState('');
  const [bulkSaving, setBulkSaving] = useState(false);
  const [selectedUndetected, setSelectedUndetected] = useState<Set<string>>(new Set());
  const { toast } = useToast();
  const { impersonateUser } = useAuth();
  const { navigate } = useRouter();

  const load = async () => {
    setError(''); setLoading(true);
    try { setUsers(await adminListUsers(search || undefined)); }
    catch (e) { setError(getErrorMessage(e, 'Failed to load users')); }
    finally { setLoading(false); }
  };
  const loadUndetected = async () => {
    setUndetectedLoading(true);
    try { setUndetected(await adminListUndetectedUsers()); }
    catch { setUndetected([]); }
    finally { setUndetectedLoading(false); }
  };
  useEffect(() => { load(); loadUndetected(); }, []);

  const handleStatusChange = async () => {
    if (!statusTarget) return;
    try {
      await adminSetUserStatus(statusTarget.id, statusTarget.status);
      toast('User status updated', 'success');
      setStatusTarget(null);
      load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to update user'), 'error');
    }
  };

  const handleRoleChange = async () => {
    if (!roleTarget) return;
    try {
      await adminSetUserRole(roleTarget.id, roleTarget.role);
      toast('User role updated', 'success');
      setRoleTarget(null);
      load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to update role'), 'error');
    }
  };

  const openBalanceModal = (user: AdminUserRow, currency: 'USDT' | 'XC', action: 'ADD' | 'SUBTRACT') => {
    setBalanceTarget(user);
    setAdjustCurrency(currency);
    setAdjustAction(action);
    setAdjustAmount('');
    setAdjustReason('');
    setAdjustStep('form');
  };

  const handleBalanceAdjustSubmit = () => {
    const amount = parseFloat(adjustAmount);
    if (isNaN(amount) || amount <= 0) { toast('Amount must be greater than zero', 'error'); return; }
    if (!adjustReason.trim()) { toast('Reason is required', 'error'); return; }
    setAdjustStep('confirm');
  };

  const handleBalanceAdjustConfirm = async () => {
    if (!balanceTarget) return;
    const amount = parseFloat(adjustAmount);
    setAdjustSubmitting(true);
    try {
      await adminAdjustUserBalance(balanceTarget.id, adjustCurrency, adjustAction, amount, adjustReason.trim());
      const amountStr = adjustCurrency === 'USDT' ? formatMoney(amount) : `${formatXc(amount)} XC`;
      const verb = adjustAction === 'ADD' ? 'increased' : 'decreased';
      toast(`${adjustCurrency} balance successfully ${verb} by ${amountStr}${adjustCurrency === 'XC' ? ' XC' : '.'}`, 'success');
      setBalanceTarget(null);
      setAdjustAmount('');
      setAdjustReason('');
      setAdjustStep('form');
      load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to adjust balance'), 'error');
      setAdjustStep('form');
    } finally {
      setAdjustSubmitting(false);
    }
  };

  const closeBalanceModal = () => {
    setBalanceTarget(null);
    setAdjustAmount('');
    setAdjustReason('');
    setAdjustStep('form');
  };

  const handleImpersonate = async (userId: string, username: string) => {
    setImpersonating(true);
    try {
      const result = await adminImpersonateUser(userId);
      await impersonateUser(userId, username, result.access_token, result.refresh_token);
      toast(`Now viewing as ${username}`, 'success');
      navigate('/dashboard');
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to impersonate user'), 'error');
    } finally {
      setImpersonating(false);
    }
  };

  const handleCountrySave = async () => {
    if (!countryTarget) return;
    setCountrySaving(true);
    try {
      await adminUpdateUserCountry(countryTarget.id, countryTarget.country);
      toast('Country updated', 'success');
      setCountryTarget(null);
      load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to update country'), 'error');
    } finally {
      setCountrySaving(false);
    }
  };
  const toggleUndetected = (id: string) => {
    setSelectedUndetected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };
  const toggleAllUndetected = () => {
    setSelectedUndetected((prev) => {
      if (prev.size === undetected.length) return new Set();
      return new Set(undetected.map((u) => u.id));
    });
  };
  const handleBulkSetCountry = async () => {
    if (selectedUndetected.size === 0) { toast('Select at least one user', 'error'); return; }
    if (!bulkCountry) { toast('Choose a country', 'error'); return; }
    setBulkSaving(true);
    try {
      const result = await adminBulkSetCountry([...selectedUndetected], bulkCountry);
      toast(`Country set for ${result.updated_count} user${result.updated_count === 1 ? '' : 's'}`, 'success');
      setSelectedUndetected(new Set());
      setBulkCountry('');
      loadUndetected();
      load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to bulk set country'), 'error');
    } finally {
      setBulkSaving(false);
    }
  };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Users" subtitle="Manage platform users" />
      <div className="flex gap-2 mb-4">
        <div className="relative flex-1 max-w-xs">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search users..." className="input pl-10" onKeyDown={(e) => e.key === 'Enter' && load()} />
        </div>
        <button onClick={load} className="btn-secondary">Search</button>
      </div>
      {undetectedLoading ? (
        <div className="card p-4 mb-4 flex items-center gap-2 text-sm text-gray-500">
          <Spinner size={14} /> Checking for undetected country users...
        </div>
      ) : undetected.length > 0 && (
        <div className="card p-4 mb-4 border border-warning-500/30">
          <div className="flex items-center gap-2 mb-3">
            <MapPin size={16} className="text-warning-500" />
            <h3 className="text-sm font-semibold text-gray-200">Undetected Country Users ({undetected.length})</h3>
          </div>
          <p className="text-xs text-gray-500 mb-3">These users have no detected country and will be rejected from any country-restricted task. Select users and assign a country, or wait for them to log in again (auto-detection runs at login).</p>
          <div className="overflow-x-auto mb-3">
            <table className="w-full">
              <thead><tr>
                <th className="table-header w-8"><input type="checkbox" checked={selectedUndetected.size === undetected.length && undetected.length > 0} onChange={toggleAllUndetected} /></th>
                <th className="table-header">User</th><th className="table-header hidden sm:table-cell">Email</th><th className="table-header hidden sm:table-cell">Joined</th>
              </tr></thead>
              <tbody className="divide-y divide-ink-700">
                {undetected.map((u) => (
                  <tr key={u.id} className="hover:bg-ink-800/50">
                    <td className="table-cell"><input type="checkbox" checked={selectedUndetected.has(u.id)} onChange={() => toggleUndetected(u.id)} /></td>
                    <td className="table-cell font-medium text-gray-200">{u.username}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-500">{u.email ?? '—'}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-500">{formatDate(u.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-gray-500">{selectedUndetected.size} selected</span>
            <select value={bulkCountry} onChange={(e) => setBulkCountry(e.target.value)} className="input max-w-[200px]">
              <option value="">Select country...</option>
              {COUNTRY_LIST.map((c) => (<option key={c.code} value={c.code}>{c.name}</option>))}
            </select>
            <button onClick={handleBulkSetCountry} disabled={bulkSaving || selectedUndetected.size === 0 || !bulkCountry} className="btn-primary text-xs">
              {bulkSaving ? <Spinner size={14} /> : 'Set Country'}
            </button>
          </div>
        </div>
      )}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-ink-800"><tr>
              <th className="table-header">User</th><th className="table-header hidden sm:table-cell">Upline / Referred By</th>
              <th className="table-header">Country</th>
              <th className="table-header">Role</th><th className="table-header">Status</th>
              <th className="table-header hidden sm:table-cell">Balance</th><th className="table-header hidden sm:table-cell">XC</th><th className="table-header hidden sm:table-cell">Ad Balance</th><th className="table-header hidden sm:table-cell">Joined</th>
              <th className="table-header">Actions</th>
            </tr></thead>
            <tbody className="divide-y divide-ink-700">
              {users.map((u) => (
                <tr key={u.id} className="hover:bg-ink-800/50">
                  <td className="table-cell"><div className="font-medium text-gray-200">{u.username}</div><div className="text-xs text-gray-500">{u.email}</div></td>
                  <td className="table-cell hidden sm:table-cell text-gray-400">{u.referrer_username ?? 'None'}</td>
                  <td className="table-cell">
                    <button
                      onClick={() => setCountryTarget({ id: u.id, country: u.country })}
                      className="flex items-center gap-1 text-xs text-gray-300 hover:text-brand-400 transition"
                      title="Edit country"
                    >
                      <MapPin size={11} />
                      {u.country ? (COUNTRY_NAME_MAP[u.country] ?? u.country) : '—'}
                    </button>
                  </td>
                  <td className="table-cell">
                    <select
                      value={u.role}
                      onChange={(e) => setRoleTarget({ id: u.id, role: e.target.value })}
                      className="bg-ink-800 border border-ink-700 rounded-lg px-2 py-1 text-xs text-gray-200"
                    >
                      <option value="user">user</option><option value="advertiser">advertiser</option><option value="admin">admin</option>
                    </select>
                  </td>
                  <td className="table-cell">
                    <select
                      value={u.status}
                      onChange={(e) => setStatusTarget({ id: u.id, status: e.target.value })}
                      className="bg-ink-800 border border-ink-700 rounded-lg px-2 py-1 text-xs text-gray-200"
                    >
                      <option value="active">Active</option><option value="suspended">Suspend</option><option value="banned">Ban</option>
                    </select>
                  </td>
                  <td className="table-cell hidden sm:table-cell font-mono text-brand-400">{formatMoney(u.available_balance)}</td>
                  <td className="table-cell hidden sm:table-cell font-mono text-brand-400">{formatXc(u.xc_balance)}</td>
                  <td className="table-cell hidden sm:table-cell font-mono text-gray-400">{formatMoney(u.advertising_balance)}</td>
                  <td className="table-cell hidden sm:table-cell text-gray-500">{formatDate(u.created_at)}</td>
                  <td className="table-cell">
                    <div className="flex gap-1.5">
                      <button
                        onClick={() => handleImpersonate(u.id, u.username)}
                        disabled={impersonating || u.role === 'admin'}
                        className="btn-secondary text-xs"
                        title={u.role === 'admin' ? 'Cannot impersonate admin' : 'Login as this user'}
                      >
                        <LogIn size={12} /> Login
                      </button>
                      <button onClick={() => openBalanceModal(u, 'USDT', 'ADD')} className="btn-secondary text-xs" title="Adjust balance">
                        <DollarSign size={12} /> Balance
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      <ConfirmDialog open={!!statusTarget} onClose={() => setStatusTarget(null)} onConfirm={handleStatusChange}
        title="Change user status" message="Are you sure you want to change this user's status?" confirmLabel="Confirm" danger />
      <ConfirmDialog open={!!roleTarget} onClose={() => setRoleTarget(null)} onConfirm={handleRoleChange}
        title="Change user role" message={`Are you sure you want to set this user's role to ${roleTarget?.role}?`} confirmLabel="Confirm" />
      <Modal open={!!countryTarget} onClose={() => setCountryTarget(null)} title="Edit User Country">
        {countryTarget && (
          <div className="space-y-4">
            <p className="text-sm text-gray-400">Override the detected country for this user. This takes precedence over automatic detection.</p>
            <div>
              <label className="label">Country</label>
              <select
                value={countryTarget.country}
                onChange={(e) => setCountryTarget({ ...countryTarget, country: e.target.value })}
                className="input"
              >
                <option value="">— None —</option>
                {COUNTRY_LIST.map((c) => (
                  <option key={c.code} value={c.code}>{c.name}</option>
                ))}
              </select>
            </div>
            <div className="flex gap-2">
              <button onClick={() => setCountryTarget(null)} className="btn-secondary flex-1" disabled={countrySaving}>Cancel</button>
              <button onClick={handleCountrySave} className="btn-primary flex-1" disabled={countrySaving}>
                {countrySaving ? <Spinner size={16} /> : 'Save'}
              </button>
            </div>
          </div>
        )}
      </Modal>
      <Modal open={!!balanceTarget} onClose={closeBalanceModal} title={adjustStep === 'confirm' ? 'Confirm Balance Adjustment' : `Adjust ${adjustCurrency} Balance`}>
        {balanceTarget && adjustStep === 'form' && (
          <div className="space-y-4">
            <p className="text-sm text-gray-400">User: <span className="font-medium text-gray-200">{balanceTarget.username}</span></p>
            <div className="grid grid-cols-2 gap-3">
              <div className="card p-3 border border-ink-700">
                <div className="text-xs text-gray-500 mb-1">Current USDT</div>
                <div className="text-lg font-mono font-bold text-brand-400">{formatMoney(balanceTarget.available_balance)}</div>
              </div>
              <div className="card p-3 border border-ink-700">
                <div className="text-xs text-gray-500 mb-1">Current XC</div>
                <div className="text-lg font-mono font-bold text-brand-400">{formatXc(balanceTarget.xc_balance)} XC</div>
              </div>
            </div>
            <div>
              <label className="label">Currency</label>
              <div className="flex gap-2">
                <button type="button" onClick={() => setAdjustCurrency('USDT')} className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition ${adjustCurrency === 'USDT' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}>USDT</button>
                <button type="button" onClick={() => setAdjustCurrency('XC')} className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition ${adjustCurrency === 'XC' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}>XC</button>
              </div>
            </div>
            <div>
              <label className="label">Action</label>
              <div className="flex gap-2">
                <button type="button" onClick={() => setAdjustAction('ADD')} className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition flex items-center justify-center gap-1.5 ${adjustAction === 'ADD' ? 'bg-green-500/15 border-green-500 text-green-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}><Plus size={14} /> Add</button>
                <button type="button" onClick={() => setAdjustAction('SUBTRACT')} className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition flex items-center justify-center gap-1.5 ${adjustAction === 'SUBTRACT' ? 'bg-danger-500/15 border-danger-500 text-danger-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}><Minus size={14} /> Subtract</button>
              </div>
            </div>
            <div>
              <label className="label">Amount</label>
              <input type="number" step="0.01" min="0" value={adjustAmount} onChange={(e) => setAdjustAmount(e.target.value)} className="input" placeholder={adjustCurrency === 'USDT' ? 'e.g. 10.00' : 'e.g. 50.00'} />
            </div>
            <div>
              <label className="label">Reason</label>
              <input value={adjustReason} onChange={(e) => setAdjustReason(e.target.value)} className="input" placeholder="e.g. Manual correction, Compensation, Fraud reversal" />
            </div>
            <div className="flex gap-2">
              <button onClick={closeBalanceModal} className="btn-secondary flex-1">Cancel</button>
              <button onClick={handleBalanceAdjustSubmit} className="btn-primary flex-1">Continue</button>
            </div>
          </div>
        )}
        {balanceTarget && adjustStep === 'confirm' && (
          <div className="space-y-4">
            <div className="card p-4 border border-ink-700 space-y-2">
              <div className="flex justify-between text-sm"><span className="text-gray-500">User</span><span className="font-medium text-gray-200">{balanceTarget.username}</span></div>
              <div className="flex justify-between text-sm"><span className="text-gray-500">Currency</span><span className={`font-mono font-semibold ${adjustCurrency === 'XC' ? 'text-brand-400' : 'text-gray-200'}`}>{adjustCurrency}</span></div>
              <div className="flex justify-between text-sm"><span className="text-gray-500">Action</span><span className={`font-medium ${adjustAction === 'ADD' ? 'text-green-400' : 'text-danger-400'}`}>{adjustAction}</span></div>
              <div className="flex justify-between text-sm"><span className="text-gray-500">Amount</span><span className="font-mono font-semibold text-gray-200">{adjustCurrency === 'USDT' ? formatMoney(parseFloat(adjustAmount) || 0) : `${formatXc(parseFloat(adjustAmount) || 0)} XC`}</span></div>
              <div className="flex justify-between text-sm"><span className="text-gray-500">Current Balance</span><span className="font-mono text-gray-300">{adjustCurrency === 'USDT' ? formatMoney(balanceTarget.available_balance) : `${formatXc(balanceTarget.xc_balance)} XC`}</span></div>
              <div className="flex justify-between text-sm border-t border-ink-700 pt-2"><span className="text-gray-500">New Balance</span><span className="font-mono font-bold text-brand-400">{adjustCurrency === 'USDT' ? formatMoney(adjustAction === 'ADD' ? balanceTarget.available_balance + (parseFloat(adjustAmount) || 0) : balanceTarget.available_balance - (parseFloat(adjustAmount) || 0)) : `${formatXc(adjustAction === 'ADD' ? balanceTarget.xc_balance + (parseFloat(adjustAmount) || 0) : balanceTarget.xc_balance - (parseFloat(adjustAmount) || 0))} XC`}</span></div>
              <div className="flex justify-between text-sm border-t border-ink-700 pt-2"><span className="text-gray-500">Reason</span><span className="text-gray-300 text-right max-w-[60%]">{adjustReason}</span></div>
            </div>
            <p className="text-xs text-gray-500">This action will be permanently recorded in the transaction ledger.</p>
            <div className="flex gap-2">
              <button onClick={() => setAdjustStep('form')} className="btn-secondary flex-1" disabled={adjustSubmitting}>Back</button>
              <button onClick={handleBalanceAdjustConfirm} className="btn-primary flex-1" disabled={adjustSubmitting}>{adjustSubmitting ? <Spinner /> : 'Confirm Adjustment'}</button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

/* ---------- Admin PTC Management ---------- */

export function AdminPtcPage() {
  const { toast } = useToast();
  const [ads, setAds] = useState<PtcAd[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<PtcAd | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<PtcAd | null>(null);
  const [form, setForm] = useState({ title: '', description: '', advertiser: '', category: 'general', reward: '0.001', duration_seconds: '10', destination_url: '', image_url: '', daily_view_limit: '1', total_view_limit: '1000', active: true });

  const load = async () => {
    setError(''); setLoading(true);
    try {
      const { data, error: e } = await supabase.from('ptc_ads').select('*').order('created_at', { ascending: false });
      if (e) throw e;
      setAds(data as PtcAd[]);
    } catch (e) { setError(getErrorMessage(e, 'Failed to load ads')); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const startEdit = (ad: PtcAd) => {
    setEditing(ad);
    setForm({ title: ad.title, description: ad.description, advertiser: ad.advertiser, category: ad.category, reward: String(ad.reward), duration_seconds: String(ad.duration_seconds), destination_url: ad.destination_url, image_url: ad.image_url, daily_view_limit: String(ad.daily_view_limit), total_view_limit: String(ad.total_view_limit), active: ad.active });
    setShowForm(true);
  };

  const startCreate = () => {
    setEditing(null);
    setForm({ title: '', description: '', advertiser: '', category: 'general', reward: '0.001', duration_seconds: '10', destination_url: '', image_url: '', daily_view_limit: '1', total_view_limit: '1000', active: true });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload = { title: form.title, description: form.description, advertiser: form.advertiser, category: form.category, reward: parseFloat(form.reward), duration_seconds: parseInt(form.duration_seconds), destination_url: form.destination_url, image_url: form.image_url, daily_view_limit: parseInt(form.daily_view_limit), total_view_limit: parseInt(form.total_view_limit), active: form.active };
    try {
      if (editing) await adminUpdatePtcAd(editing.id, payload);
      else await adminCreatePtcAd(payload);
      toast(editing ? 'Ad updated' : 'Ad created', 'success');
      setShowForm(false); load();
    } catch (e) { toast(getErrorMessage(e, 'Failed to save ad'), 'error'); }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try { await adminDeletePtcAd(deleteTarget.id); toast('Ad deleted', 'success'); load(); }
    catch (e) { toast(getErrorMessage(e, 'Failed to delete ad'), 'error'); }
  };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="PTC Management" subtitle="Create and manage advertisements" action={<button onClick={startCreate} className="btn-primary text-sm"><Plus size={16} /> New Ad</button>} />
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {ads.map((ad) => (
          <div key={ad.id} className="card p-4">
            <div className="flex items-start justify-between mb-2">
              <Badge variant={ad.active ? 'success' : 'neutral'}>{ad.active ? 'Active' : 'Inactive'}</Badge>
              <div className="flex gap-1">
                <button onClick={() => startEdit(ad)} className="p-1.5 rounded-lg hover:bg-ink-700 text-gray-400"><Pencil size={14} /></button>
                <button onClick={() => setDeleteTarget(ad)} className="p-1.5 rounded-lg hover:bg-ink-700 text-danger-500"><Trash2 size={14} /></button>
              </div>
            </div>
            <h3 className="text-sm font-semibold text-gray-100 mb-1">{ad.title}</h3>
            <p className="text-xs text-gray-500 mb-2 line-clamp-2">{ad.description}</p>
            <div className="flex items-center justify-between text-xs">
              <span className="text-gray-500">{ad.duration_seconds}s · {ad.total_views} views</span>
              <span className="font-mono font-semibold text-brand-400">{formatMoney(ad.reward)}</span>
            </div>
          </div>
        ))}
      </div>
      {ads.length === 0 && <EmptyState title="No ads yet" message="Create your first advertisement." icon={<MousePointerClick size={24} />} />}

      <Modal open={showForm} onClose={() => setShowForm(false)} title={editing ? 'Edit Ad' : 'New Ad'} maxWidth="max-w-lg">
        <form onSubmit={handleSubmit} className="space-y-3">
          <div><label className="label">Title</label><input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="input" /></div>
          <div><label className="label">Description</label><textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={2} className="input resize-none" /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Advertiser</label><input value={form.advertiser} onChange={(e) => setForm({ ...form, advertiser: e.target.value })} className="input" /></div>
            <div><label className="label">Category</label><input value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} className="input" /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Reward ($)</label><input type="number" step="0.0001" required value={form.reward} onChange={(e) => setForm({ ...form, reward: e.target.value })} className="input" /></div>
            <div><label className="label">Duration (sec)</label><input type="number" required value={form.duration_seconds} onChange={(e) => setForm({ ...form, duration_seconds: e.target.value })} className="input" /></div>
          </div>
          <div><label className="label">Destination URL</label><input value={form.destination_url} onChange={(e) => setForm({ ...form, destination_url: e.target.value })} className="input" /></div>
          <div><label className="label">Image URL</label><input value={form.image_url} onChange={(e) => setForm({ ...form, image_url: e.target.value })} className="input" /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Daily Limit</label><input type="number" value={form.daily_view_limit} onChange={(e) => setForm({ ...form, daily_view_limit: e.target.value })} className="input" /></div>
            <div><label className="label">Total Limit</label><input type="number" value={form.total_view_limit} onChange={(e) => setForm({ ...form, total_view_limit: e.target.value })} className="input" /></div>
          </div>
          <label className="flex items-center gap-2 text-sm text-gray-300"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> Active</label>
          <button type="submit" className="btn-primary w-full">{editing ? 'Update Ad' : 'Create Ad'}</button>
        </form>
      </Modal>
      <ConfirmDialog open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={handleDelete} title="Delete ad" message="This will permanently delete the advertisement." confirmLabel="Delete" danger />
    </div>
  );
}

/* ---------- Admin Task Management ---------- */

export function AdminTasksPage() {
  const { toast } = useToast();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [pending, setPending] = useState<TaskCompletion[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Task | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Task | null>(null);
  const [tab, setTab] = useState<'list' | 'review'>('list');
  const [form, setForm] = useState({ title: '', description: '', instructions: '', category: 'general', task_type: 'visit_website', reward: '0.01', action_url: '', proof_required: false, proof_instructions: '', daily_limit: '1', total_limit: '1000', active: true });

  const load = async () => {
    setError(''); setLoading(true);
    try {
      const { data: td, error: te } = await supabase.from('tasks').select('*').order('created_at', { ascending: false });
      if (te) throw te;
      setTasks(td as Task[]);
      setPending(await adminListPendingTasks());
    } catch (e) { setError(getErrorMessage(e, 'Failed to load tasks')); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const startEdit = (t: Task) => {
    setEditing(t);
    setForm({ title: t.title, description: t.description, instructions: t.instructions, category: t.category, task_type: t.task_type, reward: String(t.reward), action_url: t.action_url, proof_required: t.proof_required, proof_instructions: t.proof_instructions, daily_limit: String(t.daily_limit), total_limit: String(t.total_limit), active: t.active });
    setShowForm(true);
  };
  const startCreate = () => {
    setEditing(null);
    setForm({ title: '', description: '', instructions: '', category: 'general', task_type: 'visit_website', reward: '0.01', action_url: '', proof_required: false, proof_instructions: '', daily_limit: '1', total_limit: '1000', active: true });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload = { title: form.title, description: form.description, instructions: form.instructions, category: form.category, task_type: form.task_type, reward: parseFloat(form.reward), action_url: form.action_url, proof_required: form.proof_required, proof_instructions: form.proof_instructions, daily_limit: parseInt(form.daily_limit), total_limit: parseInt(form.total_limit), active: form.active };
    try {
      if (editing) await adminUpdateTask(editing.id, payload);
      else await adminCreateTask(payload);
      toast(editing ? 'Task updated' : 'Task created', 'success');
      setShowForm(false); load();
    } catch (e) { toast(getErrorMessage(e, 'Failed to save task'), 'error'); }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try { await adminDeleteTask(deleteTarget.id); toast('Task deleted', 'success'); load(); }
    catch (e) { toast(getErrorMessage(e, 'Failed to delete task'), 'error'); }
  };

  const handleReview = async (completionId: string, approve: boolean) => {
    try { await adminReviewTask(completionId, approve); toast(approve ? 'Task approved' : 'Task rejected', 'success'); load(); }
    catch (e) { toast(getErrorMessage(e, 'Failed to review task'), 'error'); }
  };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Task Management" subtitle="Create tasks and review submissions"
        action={tab === 'list' ? <button onClick={startCreate} className="btn-primary text-sm"><Plus size={16} /> New Task</button> : undefined} />
      <div className="flex gap-2 mb-4">
        <button onClick={() => setTab('list')} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${tab === 'list' ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>All Tasks</button>
        <button onClick={() => setTab('review')} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${tab === 'review' ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>Pending Review ({pending.length})</button>
      </div>

      {tab === 'list' ? (
        <>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {tasks.map((t) => (
              <div key={t.id} className="card p-4">
                <div className="flex items-start justify-between mb-2">
                  <Badge variant={t.active ? 'success' : 'neutral'}>{t.active ? 'Active' : 'Inactive'}</Badge>
                  <div className="flex gap-1">
                    <button onClick={() => startEdit(t)} className="p-1.5 rounded-lg hover:bg-ink-700 text-gray-400"><Pencil size={14} /></button>
                    <button onClick={() => setDeleteTarget(t)} className="p-1.5 rounded-lg hover:bg-ink-700 text-danger-500"><Trash2 size={14} /></button>
                  </div>
                </div>
                <h3 className="text-sm font-semibold text-gray-100 mb-1">{t.title}</h3>
                <p className="text-xs text-gray-500 mb-2 line-clamp-2">{t.description}</p>
                <div className="flex items-center justify-between text-xs">
                  <span className="text-gray-500">{t.task_type.replace('_', ' ')} · {t.total_completions} done</span>
                  <span className="font-mono font-semibold text-brand-400">{formatMoney(t.reward)}</span>
                </div>
              </div>
            ))}
          </div>
          {tasks.length === 0 && <EmptyState title="No tasks yet" message="Create your first task." icon={<ListChecks size={24} />} />}
        </>
      ) : (
        <div className="space-y-3">
          {pending.length === 0 ? <EmptyState title="No pending submissions" message="All task submissions have been reviewed." icon={<Check size={24} />} /> :
            pending.map((c) => (
              <div key={c.id} className="card p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-sm font-medium text-gray-200">{(c as unknown as { tasks?: { title?: string } }).tasks?.title ?? 'Task'}</div>
                    <p className="text-xs text-gray-500 mt-1">Proof: {c.proof_text || 'No proof submitted'}</p>
                    <div className="text-xs text-gray-500 mt-1">{formatDateTime(c.created_at)} · Reward: {formatMoney(c.reward)}</div>
                  </div>
                  <div className="flex gap-2 shrink-0">
                    <button onClick={() => handleReview(c.id, true)} className="btn-secondary text-xs text-success-500"><Check size={14} /> Approve</button>
                    <button onClick={() => handleReview(c.id, false)} className="btn-secondary text-xs text-danger-500"><X size={14} /> Reject</button>
                  </div>
                </div>
              </div>
            ))}
        </div>
      )}

      <Modal open={showForm} onClose={() => setShowForm(false)} title={editing ? 'Edit Task' : 'New Task'} maxWidth="max-w-lg">
        <form onSubmit={handleSubmit} className="space-y-3">
          <div><label className="label">Title</label><input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="input" /></div>
          <div><label className="label">Description</label><textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={2} className="input resize-none" /></div>
          <div><label className="label">Instructions</label><textarea value={form.instructions} onChange={(e) => setForm({ ...form, instructions: e.target.value })} rows={3} className="input resize-none" /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Category</label><input value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} className="input" /></div>
            <div><label className="label">Task Type</label>
              <select value={form.task_type} onChange={(e) => setForm({ ...form, task_type: e.target.value })} className="input">
                <option value="visit_website">Visit Website</option><option value="registration">Registration</option>
                <option value="social_follow">Social Follow</option><option value="app_install">App Install</option>
                <option value="survey">Survey</option><option value="submit_proof">Submit Proof</option><option value="custom">Custom</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Reward ($)</label><input type="number" step="0.001" required value={form.reward} onChange={(e) => setForm({ ...form, reward: e.target.value })} className="input" /></div>
            <div><label className="label">Action URL</label><input value={form.action_url} onChange={(e) => setForm({ ...form, action_url: e.target.value })} className="input" /></div>
          </div>
          <label className="flex items-center gap-2 text-sm text-gray-300"><input type="checkbox" checked={form.proof_required} onChange={(e) => setForm({ ...form, proof_required: e.target.checked })} /> Proof Required</label>
          {form.proof_required && <div><label className="label">Proof Instructions</label><input value={form.proof_instructions} onChange={(e) => setForm({ ...form, proof_instructions: e.target.value })} className="input" /></div>}
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Daily Limit</label><input type="number" value={form.daily_limit} onChange={(e) => setForm({ ...form, daily_limit: e.target.value })} className="input" /></div>
            <div><label className="label">Total Limit</label><input type="number" value={form.total_limit} onChange={(e) => setForm({ ...form, total_limit: e.target.value })} className="input" /></div>
          </div>
          <label className="flex items-center gap-2 text-sm text-gray-300"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> Active</label>
          <button type="submit" className="btn-primary w-full">{editing ? 'Update Task' : 'Create Task'}</button>
        </form>
      </Modal>
      <ConfirmDialog open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={handleDelete} title="Delete task" message="This will permanently delete the task." confirmLabel="Delete" danger />
    </div>
  );
}

/* ---------- Admin Deposits ---------- */

export function AdminDepositsPage() {
  const { toast } = useToast();
  const [deposits, setDeposits] = useState<AdminDepositRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState<string | undefined>('pending');
  const [rejectTarget, setRejectTarget] = useState<AdminDepositRow | null>(null);
  const [rejectNote, setRejectNote] = useState('');

  const load = async () => { setError(''); setLoading(true); try { setDeposits(await adminListDeposits(filter)); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, [filter]);

  const handleApprove = async (id: string) => { try { await adminApproveDeposit(id); toast('Deposit approved', 'success'); load(); } catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); } };
  const handleReject = async () => { if (!rejectTarget) return; try { await adminRejectDeposit(rejectTarget.id, rejectNote); toast('Deposit rejected', 'success'); setRejectTarget(null); setRejectNote(''); load(); } catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); } };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Deposits" subtitle="Review and process deposit requests" />
      <div className="flex gap-2 mb-4">
        {[undefined, 'pending', 'approved', 'rejected'].map((s) => (
          <button key={s ?? 'all'} onClick={() => setFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${filter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ?? 'All'}</button>
        ))}
      </div>
      {deposits.length === 0 ? <EmptyState title="No deposits" icon={<ArrowDownToLine size={24} />} /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="w-full">
          <thead className="bg-ink-800"><tr><th className="table-header">User</th><th className="table-header">Amount</th><th className="table-header">Method</th><th className="table-header">Status</th><th className="table-header hidden sm:table-cell">Date</th><th className="table-header">Actions</th></tr></thead>
          <tbody className="divide-y divide-ink-700">
            {deposits.map((d) => (
              <tr key={d.id} className="hover:bg-ink-800/50">
                <td className="table-cell"><div className="font-medium text-gray-200">{d.username}</div><div className="text-xs text-gray-500">{d.email}</div></td>
                <td className="table-cell font-mono text-brand-400">{formatMoney(d.amount)}</td>
                <td className="table-cell">{d.payment_method}</td>
                <td className="table-cell"><Badge variant={d.status === 'approved' ? 'success' : d.status === 'pending' ? 'warning' : 'danger'}>{d.status}</Badge></td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{formatDateTime(d.created_at)}</td>
                <td className="table-cell">{d.status === 'pending' && <div className="flex gap-1"><button onClick={() => handleApprove(d.id)} className="p-1.5 rounded-lg bg-success-500/10 text-success-500 hover:bg-success-500/20"><Check size={14} /></button><button onClick={() => setRejectTarget(d)} className="p-1.5 rounded-lg bg-danger-500/10 text-danger-500 hover:bg-danger-500/20"><X size={14} /></button></div>}</td>
              </tr>
            ))}
          </tbody>
        </table></div></div>
      )}
      <Modal open={!!rejectTarget} onClose={() => setRejectTarget(null)} title="Reject Deposit">
        <div className="space-y-3">
          <input value={rejectNote} onChange={(e) => setRejectNote(e.target.value)} placeholder="Reason for rejection..." className="input" />
          <button onClick={handleReject} className="btn-danger w-full">Reject Deposit</button>
        </div>
      </Modal>
    </div>
  );
}

/* ---------- Admin Withdrawals ---------- */

export function AdminWithdrawalsPage() {
  const { toast } = useToast();
  const [withdrawals, setWithdrawals] = useState<AdminWithdrawalRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState<string | undefined>('pending');
  const [rejectTarget, setRejectTarget] = useState<AdminWithdrawalRow | null>(null);
  const [rejectNote, setRejectNote] = useState('');

  const load = async () => { setError(''); setLoading(true); try { setWithdrawals(await adminListWithdrawals(filter)); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, [filter]);

  const handleApprove = async (id: string) => { try { await adminApproveWithdrawal(id); toast('Withdrawal approved', 'success'); load(); } catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); } };
  const handleReject = async () => { if (!rejectTarget) return; try { await adminRejectWithdrawal(rejectTarget.id, rejectNote); toast('Withdrawal rejected', 'success'); setRejectTarget(null); setRejectNote(''); load(); } catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); } };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Withdrawals" subtitle="Process withdrawal requests" />
      <div className="flex gap-2 mb-4">
        {[undefined, 'pending', 'paid', 'rejected'].map((s) => (
          <button key={s ?? 'all'} onClick={() => setFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${filter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ?? 'All'}</button>
        ))}
      </div>
      {withdrawals.length === 0 ? <EmptyState title="No withdrawals" icon={<ArrowUpFromLine size={24} />} /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="w-full">
          <thead className="bg-ink-800"><tr><th className="table-header">User</th><th className="table-header">Amount</th><th className="table-header">Method</th><th className="table-header hidden sm:table-cell">Destination</th><th className="table-header">Status</th><th className="table-header hidden sm:table-cell">Date</th><th className="table-header">Actions</th></tr></thead>
          <tbody className="divide-y divide-ink-700">
            {withdrawals.map((w) => (
              <tr key={w.id} className="hover:bg-ink-800/50">
                <td className="table-cell"><div className="font-medium text-gray-200">{w.username}</div><div className="text-xs text-gray-500">{w.email}</div></td>
                <td className="table-cell font-mono text-brand-400">{formatMoney(w.amount)}</td>
                <td className="table-cell">{w.withdrawal_method}</td>
                <td className="table-cell hidden sm:table-cell text-gray-500 truncate max-w-[150px]">{w.destination}</td>
                <td className="table-cell"><Badge variant={w.status === 'paid' ? 'success' : w.status === 'pending' ? 'warning' : 'danger'}>{w.status}</Badge></td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{formatDateTime(w.created_at)}</td>
                <td className="table-cell">{w.status === 'pending' && <div className="flex gap-1"><button onClick={() => handleApprove(w.id)} className="p-1.5 rounded-lg bg-success-500/10 text-success-500 hover:bg-success-500/20"><Check size={14} /></button><button onClick={() => setRejectTarget(w)} className="p-1.5 rounded-lg bg-danger-500/10 text-danger-500 hover:bg-danger-500/20"><X size={14} /></button></div>}</td>
              </tr>
            ))}
          </tbody>
        </table></div></div>
      )}
      <Modal open={!!rejectTarget} onClose={() => setRejectTarget(null)} title="Reject Withdrawal">
        <div className="space-y-3"><input value={rejectNote} onChange={(e) => setRejectNote(e.target.value)} placeholder="Reason for rejection..." className="input" /><button onClick={handleReject} className="btn-danger w-full">Reject Withdrawal</button></div>
      </Modal>
    </div>
  );
}

/* ---------- Admin Transactions ---------- */

export function AdminTransactionsPage() {
  const [txs, setTxs] = useState<AdminTransactionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [typeFilter, setTypeFilter] = useState<string | undefined>(undefined);
  const [currencyFilter, setCurrencyFilter] = useState<string | undefined>(undefined);
  const load = async () => { setError(''); setLoading(true); try { setTxs(await adminListTransactions(typeFilter, undefined, currencyFilter)); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, [typeFilter, currencyFilter]);
  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  return (
    <div>
      <PageHeader title="Transactions" subtitle="All platform transactions" />
      <div className="flex flex-wrap gap-2 mb-4">
        {[undefined, 'ptc_reward', 'task_reward', 'deposit', 'withdrawal', 'referral_bonus', 'advertiser_charge', 'advertiser_deposit'].map((s) => (
          <button key={s ?? 'all'} onClick={() => setTypeFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize ${typeFilter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ? s.replace('_', ' ') : 'All'}</button>
        ))}
      </div>
      <div className="flex gap-2 mb-4">
        {[undefined, 'USD', 'XC'].map((c) => (
          <button key={c ?? 'allc'} onClick={() => setCurrencyFilter(c)} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${currencyFilter === c ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{c ?? 'All Currencies'}</button>
        ))}
      </div>
      {txs.length === 0 ? <EmptyState title="No transactions" icon={<ScrollText size={24} />} /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="w-full">
          <thead className="bg-ink-800"><tr><th className="table-header">User</th><th className="table-header">Description</th><th className="table-header">Type</th><th className="table-header">Cur</th><th className="table-header">Status</th><th className="table-header hidden sm:table-cell">Date</th><th className="table-header text-right">Amount</th></tr></thead>
          <tbody className="divide-y divide-ink-700">
            {txs.map((t) => (
              <tr key={t.id} className="hover:bg-ink-800/50">
                <td className="table-cell text-gray-400">{t.username}</td>
                <td className="table-cell">{t.description}</td>
                <td className="table-cell"><Badge variant="neutral">{t.type.replace('_', ' ')}</Badge></td>
                <td className="table-cell"><span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold ${t.currency === 'XC' ? 'bg-brand-500/15 text-brand-400' : 'bg-ink-700 text-gray-400'}`}>{t.currency ?? 'USD'}</span></td>
                <td className="table-cell"><Badge variant={t.status === 'completed' ? 'success' : t.status === 'pending' ? 'warning' : 'neutral'}>{t.status}</Badge></td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{formatDateTime(t.created_at)}</td>
                <td className={`table-cell text-right font-mono font-semibold ${t.amount > 0 ? 'text-success-500' : 'text-danger-500'}`}>{t.amount > 0 ? '+' : ''}{t.currency === 'XC' ? `${formatXc(t.amount)} XC` : formatMoney(t.amount)}</td>
              </tr>
            ))}
          </tbody>
        </table></div></div>
      )}
    </div>
  );
}

/* ---------- Admin Referrals ---------- */

export function AdminReferralsPage() {
  const [refs, setRefs] = useState<AdminReferralRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const load = async () => { setError(''); setLoading(true); try { setRefs(await adminListReferrals()); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, []);
  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  return (
    <div>
      <PageHeader title="Referrals" subtitle="All referral relationships" />
      {refs.length === 0 ? <EmptyState title="No referrals" icon={<Users size={24} />} /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="w-full">
          <thead className="bg-ink-800"><tr><th className="table-header">Referrer</th><th className="table-header">Referred</th><th className="table-header">Qualified</th><th className="table-header">Reward</th><th className="table-header hidden sm:table-cell">Date</th></tr></thead>
          <tbody className="divide-y divide-ink-700">
            {refs.map((r) => (
              <tr key={r.id} className="hover:bg-ink-800/50">
                <td className="table-cell">{r.referrer}</td><td className="table-cell">{r.referred}</td>
                <td className="table-cell"><Badge variant={r.qualified ? 'success' : 'neutral'}>{r.qualified ? 'Yes' : 'No'}</Badge></td>
                <td className="table-cell font-mono text-brand-400">{formatMoney(r.reward_amount)}</td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{formatDate(r.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table></div></div>
      )}
    </div>
  );
}

/* ---------- Admin Support ---------- */

export function AdminSupportPage() {
  const { toast } = useToast();
  const [tickets, setTickets] = useState<AdminTicketRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState<string | undefined>('open');
  const [replyTarget, setReplyTarget] = useState<AdminTicketRow | null>(null);
  const [replyText, setReplyText] = useState('');

  const load = async () => { setError(''); setLoading(true); try { setTickets(await adminListTickets(filter)); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, [filter]);

  const handleReply = async () => {
    if (!replyTarget || !replyText.trim()) return;
    try { await adminReplyTicket(replyTarget.id, replyText); toast('Reply sent', 'success'); setReplyTarget(null); setReplyText(''); load(); }
    catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); }
  };
  const handleClose = async (id: string) => { try { await adminSetTicketStatus(id, 'closed'); toast('Ticket closed', 'success'); load(); } catch (e) { toast(getErrorMessage(e, 'Failed'), 'error'); } };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader title="Support" subtitle="Manage support tickets" />
      <div className="flex gap-2 mb-4">
        {[undefined, 'open', 'pending', 'closed'].map((s) => (
          <button key={s ?? 'all'} onClick={() => setFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${filter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ?? 'All'}</button>
        ))}
      </div>
      {tickets.length === 0 ? <EmptyState title="No tickets" icon={<Ticket size={24} />} /> : (
        <div className="space-y-3">
          {tickets.map((t) => (
            <div key={t.id} className="card p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h3 className="text-sm font-semibold text-gray-100">{t.subject}</h3>
                  <p className="text-xs text-gray-500 mt-1">{t.message}</p>
                  <div className="flex items-center gap-2 mt-2">
                    <Badge variant="neutral">{t.username}</Badge>
                    <Badge variant="neutral">{t.category}</Badge>
                    <Badge variant={t.priority === 'urgent' ? 'danger' : t.priority === 'high' ? 'warning' : 'neutral'}>{t.priority}</Badge>
                    <span className="text-xs text-gray-500">{formatDateTime(t.created_at)}</span>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Badge variant={t.status === 'open' ? 'success' : t.status === 'pending' ? 'warning' : 'neutral'}>{t.status}</Badge>
                  <button onClick={() => setReplyTarget(t)} className="btn-secondary text-xs"><Pencil size={12} /> Reply</button>
                  {t.status !== 'closed' && <button onClick={() => handleClose(t.id)} className="btn-secondary text-xs text-danger-500">Close</button>}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
      <Modal open={!!replyTarget} onClose={() => setReplyTarget(null)} title="Reply to Ticket">
        <div className="space-y-3">
          <p className="text-sm text-gray-400">{replyTarget?.subject}</p>
          <textarea value={replyText} onChange={(e) => setReplyText(e.target.value)} rows={4} placeholder="Type your reply..." className="input resize-none" />
          <button onClick={handleReply} className="btn-primary w-full">Send Reply</button>
        </div>
      </Modal>
    </div>
  );
}

/* ---------- Admin Audit Logs ---------- */

export function AdminAuditPage() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const load = async () => { setError(''); setLoading(true); try { setLogs(await adminListAuditLogs()); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, []);
  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  return (
    <div>
      <PageHeader title="Audit Logs" subtitle="Admin action history" />
      {logs.length === 0 ? <EmptyState title="No audit logs" icon={<FileText size={24} />} /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="w-full">
          <thead className="bg-ink-800"><tr><th className="table-header">Actor</th><th className="table-header">Action</th><th className="table-header hidden sm:table-cell">Target</th><th className="table-header hidden sm:table-cell">Date</th></tr></thead>
          <tbody className="divide-y divide-ink-700">
            {logs.map((l) => (
              <tr key={l.id} className="hover:bg-ink-800/50">
                <td className="table-cell text-gray-400">{l.actor_username ?? 'System'}</td>
                <td className="table-cell font-medium text-gray-200">{l.action}</td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{l.target_type ? `${l.target_type}:${l.target_id?.slice(0, 8)}` : '—'}</td>
                <td className="table-cell hidden sm:table-cell text-gray-500">{formatDateTime(l.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table></div></div>
      )}
    </div>
  );
}

/* ---------- Admin Settings ---------- */

export function AdminSettingsPage() {
  const { toast } = useToast();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState<AppSettings | null>(null);

  const load = async () => { setError(''); setLoading(true); try { const s = await getSettings(); setForm(s); } catch (e) { setError(getErrorMessage(e, 'Failed to load')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, []);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form) return;
    setSaving(true);
    try { await adminUpdateSettings(form); toast('Settings updated', 'success'); load(); }
    catch (e) { toast(getErrorMessage(e, 'Failed to save'), 'error'); }
    finally { setSaving(false); }
  };

  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!form) return null;

  return (
    <div>
      <PageHeader title="Settings" subtitle="Platform configuration" />
      <form onSubmit={handleSave} className="card p-6 max-w-2xl space-y-4">
        <div className="grid sm:grid-cols-2 gap-4">
          <div><label className="label">Platform Name</label><input value={form.platform_name} onChange={(e) => setForm({ ...form, platform_name: e.target.value })} className="input" /></div>
          <div><label className="label">Referral Commission — PTC & Tasks (%)</label><input type="number" step="0.1" min="0" max="100" value={form.referral_commission_percent} onChange={(e) => setForm({ ...form, referral_commission_percent: parseFloat(e.target.value) })} className="input" /></div>
        </div>
        <div><label className="label">Referral Commission — Deposits (%)</label><input type="number" step="0.1" min="0" max="100" value={form.referral_deposit_commission_percent} onChange={(e) => setForm({ ...form, referral_deposit_commission_percent: parseFloat(e.target.value) })} className="input" /></div>
        <div className="grid sm:grid-cols-2 gap-4">
          <div><label className="label">Min Withdrawal ($)</label><input type="number" step="0.01" value={form.min_withdrawal} onChange={(e) => setForm({ ...form, min_withdrawal: parseFloat(e.target.value) })} className="input" /></div>
          <div><label className="label">Max Withdrawal ($)</label><input type="number" step="0.01" value={form.max_withdrawal} onChange={(e) => setForm({ ...form, max_withdrawal: parseFloat(e.target.value) })} className="input" /></div>
        </div>
        <div className="grid sm:grid-cols-3 gap-4">
          <div><label className="label">Withdrawal Cooldown (min)</label><input type="number" value={form.withdrawal_cooldown_minutes} onChange={(e) => setForm({ ...form, withdrawal_cooldown_minutes: parseInt(e.target.value) })} className="input" /></div>
          <div><label className="label">PTC Daily Limit / Ad</label><input type="number" value={form.ptc_daily_limit_per_ad} onChange={(e) => setForm({ ...form, ptc_daily_limit_per_ad: parseInt(e.target.value) })} className="input" /></div>
          <div><label className="label">Task Daily Limit</label><input type="number" value={form.task_daily_limit} onChange={(e) => setForm({ ...form, task_daily_limit: parseInt(e.target.value) })} className="input" /></div>
        </div>
        <div className="border-t border-ink-700 pt-4 mt-4">
          <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2 mb-3"><Coins size={16} /> XC Token Settings</h3>
          <div className="grid sm:grid-cols-2 gap-4">
            <div><label className="label">Token Name</label><input value={form.xc_token_name} onChange={(e) => setForm({ ...form, xc_token_name: e.target.value })} className="input" /></div>
            <div><label className="label">Token Symbol</label><input value={form.xc_token_symbol} onChange={(e) => setForm({ ...form, xc_token_symbol: e.target.value })} className="input" /></div>
          </div>
          <div className="grid sm:grid-cols-3 gap-4 mt-3">
            <div><label className="label">XC per USD</label><input type="number" step="1" min="1" value={form.xc_per_usd} onChange={(e) => setForm({ ...form, xc_per_usd: parseFloat(e.target.value) })} className="input" /></div>
            <div><label className="label">Min Conversion ($)</label><input type="number" step="0.01" value={form.xc_min_conversion} onChange={(e) => setForm({ ...form, xc_min_conversion: parseFloat(e.target.value) })} className="input" /></div>
            <div><label className="label">Max Conversion ($)</label><input type="number" step="0.01" value={form.xc_max_conversion} onChange={(e) => setForm({ ...form, xc_max_conversion: parseFloat(e.target.value) })} className="input" /></div>
          </div>
          <label className="flex items-center gap-2 text-sm text-gray-300 mt-3"><input type="checkbox" checked={form.xc_conversion_enabled} onChange={(e) => setForm({ ...form, xc_conversion_enabled: e.target.checked })} /> Enable USD to XC Conversion</label>
        </div>
        <div className="border-t border-ink-700 pt-4 mt-4">
          <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2 mb-3"><Coins size={16} /> XC Reward Economy</h3>
          <div className="grid sm:grid-cols-2 gap-4">
            <div><label className="label">XC Reward Multiplier</label><input type="number" step="1" min="1" value={form.reward_multiplier} onChange={(e) => setForm({ ...form, reward_multiplier: parseFloat(e.target.value) })} className="input" /><p className="text-xs text-gray-500 mt-1">User reward = base USD reward x multiplier</p></div>
            <div><label className="label">XC Value (USD)</label><input type="number" step="0.01" min="0.01" value={form.xc_value_usd} onChange={(e) => setForm({ ...form, xc_value_usd: parseFloat(e.target.value) })} className="input" /><p className="text-xs text-gray-500 mt-1">1 XC = $1.00</p></div>
          </div>
        </div>
        <button type="submit" disabled={saving} className="btn-primary">{saving ? <Spinner size={18} /> : <><Settings size={16} /> Save Settings</>}</button>
      </form>
    </div>
  );
}

/* ---------- Admin Campaign Approvals ---------- */

export function AdminCampaignsPage() {
  const { toast } = useToast();
  const [data, setData] = useState<AdminPendingCampaignsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [rejectTarget, setRejectTarget] = useState<{ id: string; type: 'ptc' | 'task'; title: string } | null>(null);
  const [rejectNote, setRejectNote] = useState('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const load = async () => {
    setError(''); setLoading(true);
    try { setData(await adminListPendingCampaigns()); }
    catch (e) { setError(getErrorMessage(e, 'Failed to load campaigns')); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const handleApprove = async (id: string, type: 'ptc' | 'task') => {
    setActionLoading(id);
    try {
      await adminApproveCampaign(id, type);
      toast('Campaign approved', 'success');
      await load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to approve'), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  const handleReject = async () => {
    if (!rejectTarget) return;
    setActionLoading(rejectTarget.id);
    try {
      await adminRejectCampaign(rejectTarget.id, rejectTarget.type, rejectNote);
      toast('Campaign rejected and budget refunded', 'success');
      setRejectTarget(null);
      setRejectNote('');
      await load();
    } catch (e) {
      toast(getErrorMessage(e, 'Failed to reject'), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) return <LoadingScreen label="Loading pending campaigns..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return null;

  const ptcCampaigns = data.ptc_campaigns ?? [];
  const taskCampaigns = data.task_campaigns ?? [];
  const total = ptcCampaigns.length + taskCampaigns.length;

  return (
    <div>
      <PageHeader title="Campaign Approvals" subtitle="Review and approve advertiser campaigns" />

      {total === 0 ? (
        <EmptyState title="No pending campaigns" message="All advertiser campaigns have been reviewed." icon={<Megaphone size={24} />} />
      ) : (
        <>
          {ptcCampaigns.length > 0 && (
            <div className="mb-6">
              <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
                <MousePointerClick size={16} /> PTC Campaigns ({ptcCampaigns.length})
              </h2>
              <div className="space-y-3">
                {ptcCampaigns.map((c) => (
                  <div key={c.id} className="card p-4">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                        <div className="flex items-center gap-2 mt-1">
                          <Badge variant="warning">pending</Badge>
                          <span className="text-xs text-gray-500">by {c.advertiser_name}</span>
                          <span className="text-xs text-gray-500">{c.category}</span>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-gray-500">Budget</div>
                        <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(c.budget)}</div>
                      </div>
                    </div>
                    <div className="grid grid-cols-3 gap-3 mb-3 text-xs">
                      <div><span className="text-gray-500">Reward/view</span><p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p></div>
                      <div><span className="text-gray-500">Est. views</span><p className="text-gray-300 font-mono">{c.reward > 0 ? Math.floor(c.budget / c.reward).toLocaleString() : '—'}</p></div>
                      <div><span className="text-gray-500">Created</span><p className="text-gray-300">{formatDate(c.created_at)}</p></div>
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
                    <div className="flex gap-2">
                      <button onClick={() => handleApprove(c.id, 'ptc')} disabled={actionLoading === c.id} className="btn-primary text-xs">
                        <Check size={14} /> Approve
                      </button>
                      <button onClick={() => setRejectTarget({ id: c.id, type: 'ptc', title: c.title })} disabled={actionLoading === c.id} className="btn-danger text-xs">
                        <X size={14} /> Reject
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {taskCampaigns.length > 0 && (
            <div className="mb-6">
              <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
                <ListChecks size={16} /> Task Campaigns ({taskCampaigns.length})
              </h2>
              <div className="space-y-3">
                {taskCampaigns.map((c) => (
                  <div key={c.id} className="card p-4">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                        <div className="flex items-center gap-2 mt-1">
                          <Badge variant="warning">pending</Badge>
                          <span className="text-xs text-gray-500">by {c.advertiser_name}</span>
                          <span className="text-xs text-gray-500 capitalize">{c.task_type.replace('_', ' ')}</span>
                          {c.proof_required && <Badge variant="brand">proof required</Badge>}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-gray-500">Budget</div>
                        <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(c.budget)}</div>
                      </div>
                    </div>
                    <div className="grid grid-cols-3 gap-3 mb-3 text-xs">
                      <div><span className="text-gray-500">Reward/task</span><p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p></div>
                      <div><span className="text-gray-500">Est. completions</span><p className="text-gray-300 font-mono">{c.reward > 0 ? Math.floor(c.budget / c.reward).toLocaleString() : '—'}</p></div>
                      <div><span className="text-gray-500">Created</span><p className="text-gray-300">{formatDate(c.created_at)}</p></div>
                    </div>
                    {c.action_url && (
                      <a href={c.action_url} target="_blank" rel="noopener noreferrer" className="text-xs text-blue-400 hover:text-blue-300 flex items-center gap-1 mb-3">
                        <ExternalLink size={12} /> {c.action_url}
                      </a>
                    )}
                    <div className="flex gap-2">
                      <button onClick={() => handleApprove(c.id, 'task')} disabled={actionLoading === c.id} className="btn-primary text-xs">
                        <Check size={14} /> Approve
                      </button>
                      <button onClick={() => setRejectTarget({ id: c.id, type: 'task', title: c.title })} disabled={actionLoading === c.id} className="btn-danger text-xs">
                        <X size={14} /> Reject
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}

      <Modal open={!!rejectTarget} onClose={() => { setRejectTarget(null); setRejectNote(''); }} title="Reject Campaign">
        <p className="text-sm text-gray-400 mb-4">
          Reject "{rejectTarget?.title}"? The full budget will be refunded to the advertiser's advertising balance.
        </p>
        <div className="mb-4">
          <label className="label">Rejection Note (optional)</label>
          <textarea value={rejectNote} onChange={(e) => setRejectNote(e.target.value)} rows={2} className="input resize-none" placeholder="Reason for rejection" />
        </div>
        <div className="flex gap-3 justify-end">
          <button onClick={() => { setRejectTarget(null); setRejectNote(''); }} className="btn-secondary">Cancel</button>
          <button onClick={handleReject} disabled={actionLoading === rejectTarget?.id} className="btn-danger">
            {actionLoading === rejectTarget?.id ? <Spinner size={16} /> : 'Reject & Refund'}
          </button>
        </div>
      </Modal>
    </div>
  );
}

/* ---------- Admin Advertisers ---------- */

export function AdminAdvertisersPage() {
  const [advertisers, setAdvertisers] = useState<AdminAdvertiserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const load = async () => {
    setError(''); setLoading(true);
    try { setAdvertisers(await adminListAdvertisers()); }
    catch (e) { setError(getErrorMessage(e, 'Failed to load advertisers')); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);
  if (loading) return <LoadingScreen />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  return (
    <div>
      <PageHeader title="Advertisers" subtitle="All advertisers on the platform" />
      {advertisers.length === 0 ? <EmptyState title="No advertisers" icon={<Megaphone size={24} />} /> : (
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-ink-800"><tr>
                <th className="table-header">Advertiser</th>
                <th className="table-header hidden sm:table-cell">Status</th>
                <th className="table-header">Ad Balance</th>
                <th className="table-header hidden sm:table-cell">PTC Campaigns</th>
                <th className="table-header hidden sm:table-cell">Task Campaigns</th>
                <th className="table-header hidden sm:table-cell">Total Spent</th>
                <th className="table-header hidden sm:table-cell">Active</th>
                <th className="table-header hidden sm:table-cell">Pending</th>
                <th className="table-header hidden sm:table-cell">Joined</th>
              </tr></thead>
              <tbody className="divide-y divide-ink-700">
                {advertisers.map((a) => (
                  <tr key={a.id} className="hover:bg-ink-800/50">
                    <td className="table-cell"><div className="font-medium text-gray-200">{a.username}</div><div className="text-xs text-gray-500">{a.email}</div></td>
                    <td className="table-cell hidden sm:table-cell"><Badge variant={a.status === 'active' ? 'success' : 'danger'}>{a.status}</Badge></td>
                    <td className="table-cell font-mono text-brand-400">{formatMoney(a.advertising_balance)}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-300">{a.ptc_campaigns}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-300">{a.task_campaigns}</td>
                    <td className="table-cell hidden sm:table-cell font-mono text-gray-300">{formatMoney(a.total_spent)}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-300">{a.active_campaigns}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-300">{a.pending_campaigns}</td>
                    <td className="table-cell hidden sm:table-cell text-gray-500">{formatDate(a.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

/* ---------- Admin All Campaigns ---------- */

export function AdminAllCampaignsPage() {
  const { toast } = useToast();
  const [data, setData] = useState<AdminAllCampaignsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [typeFilter, setTypeFilter] = useState<string | undefined>(undefined);
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const load = async () => {
    setError(''); setLoading(true);
    try { setData(await adminListAllCampaigns(typeFilter, statusFilter)); }
    catch (e) { setError(getErrorMessage(e, 'Failed to load campaigns')); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, [typeFilter, statusFilter]);

  const handleAction = async (id: string, type: 'ptc' | 'task', action: 'pause' | 'resume' | 'stop') => {
    setActionLoading(id);
    try {
      if (action === 'pause') await adminPauseCampaign(id, type);
      else if (action === 'resume') await adminResumeCampaign(id, type);
      else await adminStopCampaign(id, type);
      toast(`Campaign ${action}ed`, 'success');
      await load();
    } catch (e) {
      toast(getErrorMessage(e, `Failed to ${action} campaign`), 'error');
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) return <LoadingScreen label="Loading campaigns..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return null;

  const ptcCampaigns = (data.ptc_campaigns ?? []) as AdminAllPtcCampaign[];
  const taskCampaigns = (data.task_campaigns ?? []) as AdminAllTaskCampaign[];

  const renderCampaignActions = (c: AdminAllPtcCampaign | AdminAllTaskCampaign, type: 'ptc' | 'task') => {
    const status = c.status as CampaignStatus;
    if (status === 'completed' || status === 'rejected') return null;
    return (
      <div className="flex gap-1.5">
        {status === 'active' && (
          <button onClick={() => handleAction(c.id, type, 'pause')} disabled={actionLoading === c.id} className="btn-secondary text-xs" title="Pause">
            <Pause size={12} /> Pause
          </button>
        )}
        {status === 'paused' && (
          <button onClick={() => handleAction(c.id, type, 'resume')} disabled={actionLoading === c.id} className="btn-secondary text-xs" title="Resume">
            <Play size={12} /> Resume
          </button>
        )}
        <button onClick={() => handleAction(c.id, type, 'stop')} disabled={actionLoading === c.id} className="btn-danger text-xs" title="Stop permanently">
          <Square size={12} /> Stop
        </button>
      </div>
    );
  };

  return (
    <div>
      <PageHeader title="All Campaigns" subtitle="Manage all advertiser campaigns" />

      <div className="flex flex-wrap gap-2 mb-4">
        <div className="flex gap-1.5">
          {[undefined, 'ptc', 'task'].map((s) => (
            <button key={s ?? 'all'} onClick={() => setTypeFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium ${typeFilter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ? s.toUpperCase() : 'All Types'}</button>
          ))}
        </div>
        <div className="flex gap-1.5">
          {[undefined, 'active', 'paused', 'pending', 'completed', 'rejected'].map((s) => (
            <button key={s ?? 'all'} onClick={() => setStatusFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize ${statusFilter === s ? 'bg-brand-500 text-white' : 'bg-ink-800 text-gray-400'}`}>{s ?? 'All Status'}</button>
          ))}
        </div>
      </div>

      {ptcCampaigns.length === 0 && taskCampaigns.length === 0 ? (
        <EmptyState title="No campaigns found" message="No campaigns match the current filters." icon={<Megaphone size={24} />} />
      ) : (
        <div className="space-y-4">
          {ptcCampaigns.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
                <MousePointerClick size={16} /> PTC Campaigns ({ptcCampaigns.length})
              </h2>
              <div className="space-y-3">
                {ptcCampaigns.map((c) => (
                  <div key={c.id} className="card p-4">
                    <div className="flex items-start justify-between mb-2">
                      <div>
                        <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                        <div className="flex items-center gap-2 mt-1">
                          <Badge variant={c.status === 'active' ? 'success' : c.status === 'pending' ? 'warning' : c.status === 'rejected' ? 'danger' : 'neutral'}>{c.status}</Badge>
                          <span className="text-xs text-gray-500">by {c.advertiser_name}</span>
                          <span className="text-xs text-gray-500">{c.category}</span>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-gray-500">Spent / Budget</div>
                        <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(c.spent)} / {formatMoney(c.budget)}</div>
                      </div>
                    </div>
                    <div className="grid grid-cols-4 gap-3 mb-3 text-xs">
                      <div><span className="text-gray-500">Reward</span><p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p></div>
                      <div><span className="text-gray-500">Views</span><p className="text-gray-300 font-mono">{c.total_views.toLocaleString()}</p></div>
                      <div><span className="text-gray-500">Duration</span><p className="text-gray-300">{c.duration_seconds}s</p></div>
                      <div><span className="text-gray-500">Created</span><p className="text-gray-300">{formatDate(c.created_at)}</p></div>
                    </div>
                    {c.destination_url && (
                      <a href={c.destination_url} target="_blank" rel="noopener noreferrer" className="text-xs text-blue-400 hover:text-blue-300 flex items-center gap-1 mb-3">
                        <ExternalLink size={12} /> {c.destination_url}
                      </a>
                    )}
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
                    {renderCampaignActions(c, 'ptc')}
                  </div>
                ))}
              </div>
            </div>
          )}

          {taskCampaigns.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-gray-300 mb-3 flex items-center gap-2">
                <ListChecks size={16} /> Task Campaigns ({taskCampaigns.length})
              </h2>
              <div className="space-y-3">
                {taskCampaigns.map((c) => (
                  <div key={c.id} className="card p-4">
                    <div className="flex items-start justify-between mb-2">
                      <div>
                        <h3 className="text-sm font-semibold text-gray-100">{c.title}</h3>
                        <div className="flex items-center gap-2 mt-1">
                          <Badge variant={c.status === 'active' ? 'success' : c.status === 'pending' ? 'warning' : c.status === 'rejected' ? 'danger' : 'neutral'}>{c.status}</Badge>
                          <span className="text-xs text-gray-500">by {c.advertiser_name}</span>
                          <span className="text-xs text-gray-500 capitalize">{c.task_type.replace('_', ' ')}</span>
                          {c.proof_required && <Badge variant="brand">proof</Badge>}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-gray-500">Spent / Budget</div>
                        <div className="text-sm font-mono font-bold text-brand-400">{formatMoney(c.spent)} / {formatMoney(c.budget)}</div>
                      </div>
                    </div>
                    <div className="grid grid-cols-4 gap-3 mb-3 text-xs">
                      <div><span className="text-gray-500">Reward</span><p className="text-gray-300 font-mono">{formatMoney(c.reward)}</p></div>
                      <div><span className="text-gray-500">Completions</span><p className="text-gray-300 font-mono">{c.total_completions.toLocaleString()}</p></div>
                      <div><span className="text-gray-500">Type</span><p className="text-gray-300 capitalize">{c.task_type.replace('_', ' ')}</p></div>
                      <div><span className="text-gray-500">Created</span><p className="text-gray-300">{formatDate(c.created_at)}</p></div>
                    </div>
                    {c.action_url && (
                      <a href={c.action_url} target="_blank" rel="noopener noreferrer" className="text-xs text-blue-400 hover:text-blue-300 flex items-center gap-1 mb-3">
                        <ExternalLink size={12} /> {c.action_url}
                      </a>
                    )}
                    {renderCampaignActions(c, 'task')}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
