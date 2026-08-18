import { useEffect, useState } from 'react';
import { listMyTickets, createTicket, getTicketReplies, replyToTicket, closeTicket, getErrorMessage } from '@/lib/api';
import { useToast } from '@/lib/toast';
import { LoadingScreen, ErrorState, PageHeader, EmptyState, Badge, Modal, Spinner } from '@/components/ui';
import { formatDateTime } from '@/lib/format';
import { Ticket, Plus, Send, XCircle } from 'lucide-react';
import type { SupportTicket, TicketReply } from '@/types';

export function SupportPage() {
  const { toast } = useToast();
  const [tickets, setTickets] = useState<SupportTicket[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [activeTicket, setActiveTicket] = useState<SupportTicket | null>(null);
  const [replies, setReplies] = useState<TicketReply[]>([]);
  const [replyText, setReplyText] = useState('');
  const [replying, setReplying] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({ subject: '', message: '', category: 'general', priority: 'normal' });

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const list = await listMyTickets();
      setTickets(list);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load tickets'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await createTicket(form);
      toast('Ticket created successfully', 'success');
      setShowForm(false);
      setForm({ subject: '', message: '', category: 'general', priority: 'normal' });
      load();
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to create ticket'), 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const openTicket = async (t: SupportTicket) => {
    setActiveTicket(t);
    try {
      const r = await getTicketReplies(t.id);
      setReplies(r);
    } catch {
      setReplies([]);
    }
  };

  const handleReply = async () => {
    if (!activeTicket || !replyText.trim()) return;
    setReplying(true);
    try {
      await replyToTicket(activeTicket.id, replyText);
      setReplyText('');
      const r = await getTicketReplies(activeTicket.id);
      setReplies(r);
      toast('Reply sent', 'success');
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to send reply'), 'error');
    } finally {
      setReplying(false);
    }
  };

  const handleClose = async () => {
    if (!activeTicket) return;
    try {
      await closeTicket(activeTicket.id);
      toast('Ticket closed', 'success');
      load();
      setActiveTicket(null);
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to close ticket'), 'error');
    }
  };

  if (loading) return <LoadingScreen label="Loading tickets..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Support"
        subtitle="Get help with your account"
        action={
          <button onClick={() => setShowForm(true)} className="btn-primary text-sm">
            <Plus size={16} /> New Ticket
          </button>
        }
      />

      {tickets.length === 0 ? (
        <EmptyState
          title="No support tickets"
          message="Need help? Create a ticket and our team will assist you."
          icon={<Ticket size={24} />}
        />
      ) : (
        <div className="space-y-3">
          {tickets.map((t) => (
            <div key={t.id} className="card card-hover p-4 cursor-pointer" onClick={() => openTicket(t)}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="text-sm font-semibold text-gray-100 truncate">{t.subject}</h3>
                  </div>
                  <p className="text-xs text-gray-500 truncate">{t.message}</p>
                  <div className="flex items-center gap-2 mt-2">
                    <Badge variant="neutral">{t.category}</Badge>
                    <Badge variant={t.priority === 'urgent' ? 'danger' : t.priority === 'high' ? 'warning' : 'neutral'}>
                      {t.priority}
                    </Badge>
                    <span className="text-xs text-gray-500">{formatDateTime(t.created_at)}</span>
                  </div>
                </div>
                <Badge variant={t.status === 'open' ? 'success' : t.status === 'pending' ? 'warning' : 'neutral'}>
                  {t.status}
                </Badge>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* New ticket modal */}
      <Modal open={showForm} onClose={() => setShowForm(false)} title="New Support Ticket">
        <form onSubmit={handleCreate} className="space-y-4">
          <div>
            <label className="label">Subject</label>
            <input required value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} placeholder="Brief description of your issue" className="input" />
          </div>
          <div>
            <label className="label">Message</label>
            <textarea required value={form.message} onChange={(e) => setForm({ ...form, message: e.target.value })} rows={4} placeholder="Describe your issue in detail..." className="input resize-none" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="label">Category</label>
              <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} className="input">
                <option value="general">General</option>
                <option value="account">Account</option>
                <option value="payment">Payment</option>
                <option value="technical">Technical</option>
              </select>
            </div>
            <div>
              <label className="label">Priority</label>
              <select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} className="input">
                <option value="low">Low</option>
                <option value="normal">Normal</option>
                <option value="high">High</option>
                <option value="urgent">Urgent</option>
              </select>
            </div>
          </div>
          <button type="submit" disabled={submitting} className="btn-primary w-full">
            {submitting ? <Spinner size={18} /> : 'Create Ticket'}
          </button>
        </form>
      </Modal>

      {/* Ticket detail modal */}
      <Modal open={!!activeTicket} onClose={() => setActiveTicket(null)} title={activeTicket?.subject ?? ''} maxWidth="max-w-lg">
        {activeTicket && (
          <div>
            <div className="flex items-center gap-2 mb-4">
              <Badge variant="neutral">{activeTicket.category}</Badge>
              <Badge variant={activeTicket.status === 'open' ? 'success' : activeTicket.status === 'pending' ? 'warning' : 'neutral'}>
                {activeTicket.status}
              </Badge>
              <span className="text-xs text-gray-500">{formatDateTime(activeTicket.created_at)}</span>
            </div>

            <div className="space-y-3 mb-4 max-h-64 overflow-y-auto">
              <div className="p-3 rounded-lg bg-ink-800">
                <div className="text-xs text-gray-500 mb-1">You · {formatDateTime(activeTicket.created_at)}</div>
                <p className="text-sm text-gray-300">{activeTicket.message}</p>
              </div>
              {replies.map((r) => (
                <div key={r.id} className={`p-3 rounded-lg ${r.is_staff ? 'bg-brand-500/5 border border-brand-500/20' : 'bg-ink-800'}`}>
                  <div className="text-xs text-gray-500 mb-1">
                    {r.is_staff ? <span className="text-brand-400 font-medium">Support Staff</span> : 'You'} · {formatDateTime(r.created_at)}
                  </div>
                  <p className="text-sm text-gray-300">{r.message}</p>
                </div>
              ))}
            </div>

            {activeTicket.status !== 'closed' && (
              <div className="space-y-2">
                <textarea
                  value={replyText}
                  onChange={(e) => setReplyText(e.target.value)}
                  rows={2}
                  placeholder="Type your reply..."
                  className="input resize-none"
                />
                <div className="flex gap-2">
                  <button onClick={handleReply} disabled={replying || !replyText.trim()} className="btn-primary flex-1">
                    {replying ? <Spinner size={16} /> : <><Send size={14} /> Send Reply</>}
                  </button>
                  <button onClick={handleClose} className="btn-secondary text-danger-500">
                    <XCircle size={14} /> Close
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </Modal>
    </div>
  );
}
