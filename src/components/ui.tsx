import type { ReactNode } from 'react';
import { Loader2, Inbox, AlertTriangle } from 'lucide-react';

export function SkeletonCard() {
  return (
    <div className="card p-5 animate-pulse">
      <div className="flex items-start justify-between mb-3">
        <div className="h-3 w-24 bg-ink-700 rounded" />
        <div className="h-9 w-9 bg-ink-700 rounded-lg" />
      </div>
      <div className="h-7 w-32 bg-ink-700 rounded" />
    </div>
  );
}

export function SkeletonRow() {
  return (
    <div className="flex items-center justify-between py-3 border-b border-ink-700 last:border-0 animate-pulse">
      <div className="flex items-center gap-3">
        <div className="h-8 w-8 bg-ink-700 rounded-lg" />
        <div className="space-y-1.5">
          <div className="h-3 w-32 bg-ink-700 rounded" />
          <div className="h-2.5 w-24 bg-ink-700 rounded" />
        </div>
      </div>
      <div className="h-5 w-16 bg-ink-700 rounded" />
    </div>
  );
}

export function DashboardSkeleton() {
  return (
    <div className="animate-pulse">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {Array.from({ length: 4 }).map((_, i) => <SkeletonCard key={i} />)}
      </div>
      <div className="grid lg:grid-cols-3 gap-6 mb-6">
        <div className="card p-5 lg:col-span-2 h-48 bg-ink-850" />
        <div className="card p-5 h-48 bg-ink-850" />
      </div>
      <div className="card p-5 h-64 bg-ink-850" />
    </div>
  );
}

export function TableSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="card p-5">
      {Array.from({ length: rows }).map((_, i) => <SkeletonRow key={i} />)}
    </div>
  );
}

export function Spinner({ size = 20, className = '' }: { size?: number; className?: string }) {
  return <Loader2 size={size} className={`animate-spin text-brand-500 ${className}`} />;
}

export function LoadingScreen({ label = 'Loading...' }: { label?: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 gap-3">
      <Spinner size={32} />
      <p className="text-sm text-gray-500">{label}</p>
    </div>
  );
}

export function EmptyState({ title, message, icon }: { title: string; message?: string; icon?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
      <div className="w-14 h-14 rounded-full bg-ink-800 flex items-center justify-center mb-4 text-gray-500">
        {icon ?? <Inbox size={24} />}
      </div>
      <h3 className="text-sm font-semibold text-gray-300 mb-1">{title}</h3>
      {message && <p className="text-xs text-gray-500 max-w-sm">{message}</p>}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
      <div className="w-14 h-14 rounded-full bg-danger-500/10 flex items-center justify-center mb-4 text-danger-500">
        <AlertTriangle size={24} />
      </div>
      <h3 className="text-sm font-semibold text-gray-300 mb-1">Something went wrong</h3>
      <p className="text-xs text-gray-500 max-w-sm mb-4">{message}</p>
      {onRetry && (
        <button onClick={onRetry} className="btn-secondary text-xs">
          Try again
        </button>
      )}
    </div>
  );
}

export function StatCard({
  label,
  value,
  icon,
  accent = 'brand',
  sublabel,
}: {
  label: string;
  value: string | number;
  icon: ReactNode;
  accent?: 'brand' | 'green' | 'blue' | 'red' | 'neutral' | 'purple';
  sublabel?: string;
}) {
  const accentMap = {
    brand: 'text-brand-400 bg-brand-500/10',
    green: 'text-success-500 bg-success-500/10',
    blue: 'text-blue-400 bg-blue-500/10',
    red: 'text-danger-500 bg-danger-500/10',
    neutral: 'text-gray-400 bg-ink-800',
    purple: 'text-brand-400 bg-brand-500/10',
  };
  return (
    <div className="stat-card overflow-hidden">
      <div className="flex items-start justify-between mb-2 sm:mb-3 gap-2">
        <span className="text-[10px] sm:text-xs font-medium text-gray-500 uppercase tracking-wide leading-tight">{label}</span>
        <div className={`w-8 h-8 sm:w-9 sm:h-9 rounded-lg flex items-center justify-center shrink-0 ${accentMap[accent]}`}>
          {icon}
        </div>
      </div>
      <div className="text-lg sm:text-2xl font-bold text-gray-100 font-mono break-all leading-tight">{value}</div>
      {sublabel && <div className="text-xs text-gray-500 mt-1">{sublabel}</div>}
    </div>
  );
}

export function Modal({
  open,
  onClose,
  title,
  children,
  maxWidth = 'max-w-md',
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  maxWidth?: string;
}) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 animate-fade-in">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className={`relative card w-full ${maxWidth} max-h-[90vh] overflow-y-auto animate-slide-up`}>
        <div className="flex items-center justify-between px-5 py-4 border-b border-ink-700">
          <h2 className="text-sm font-semibold text-gray-100">{title}</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-300 text-xl leading-none">
            &times;
          </button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

export function Badge({ variant = 'neutral', children }: { variant?: 'brand' | 'success' | 'warning' | 'danger' | 'neutral'; children: ReactNode }) {
  const map = {
    brand: 'badge-brand',
    success: 'badge-success',
    warning: 'badge-warning',
    danger: 'badge-danger',
    neutral: 'badge-neutral',
  };
  return <span className={map[variant]}>{children}</span>;
}

export function PageHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="flex items-start justify-between mb-5 sm:mb-6 flex-wrap gap-3">
      <div className="min-w-0">
        <h1 className="text-lg sm:text-xl font-bold text-gray-100 truncate">{title}</h1>
        {subtitle && <p className="text-sm text-gray-500 mt-1">{subtitle}</p>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

export function ConfirmDialog({
  open,
  onClose,
  onConfirm,
  title,
  message,
  confirmLabel = 'Confirm',
  danger = false,
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  message: string;
  confirmLabel?: string;
  danger?: boolean;
}) {
  return (
    <Modal open={open} onClose={onClose} title={title}>
      <p className="text-sm text-gray-400 mb-5">{message}</p>
      <div className="flex gap-3 justify-end">
        <button onClick={onClose} className="btn-secondary">
          Cancel
        </button>
        <button
          onClick={() => {
            onConfirm();
            onClose();
          }}
          className={danger ? 'btn-danger' : 'btn-primary'}
        >
          {confirmLabel}
        </button>
      </div>
    </Modal>
  );
}
