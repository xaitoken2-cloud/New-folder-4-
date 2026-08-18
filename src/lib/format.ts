export function formatMoney(amount: number | null | undefined): string {
  const value = Number(amount ?? 0);
  return '$' + value.toFixed(4).replace(/\.?0+$/, (m) => (m.includes('.') ? m.slice(0, m.length - 2) + (m.length > 3 ? '' : '') : ''));
}

export function formatXc(amount: number | null | undefined): string {
  const value = Number(amount ?? 0);
  return value.toLocaleString('en-US', { maximumFractionDigits: 2 });
}

export function formatMoneyShort(amount: number | null | undefined): string {
  const value = Number(amount ?? 0);
  if (Math.abs(value) >= 1000) return '$' + (value / 1000).toFixed(1) + 'k';
  return '$' + value.toFixed(2);
}

export function formatDate(date: string | null | undefined): string {
  if (!date) return '—';
  return new Date(date).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function formatDateTime(date: string | null | undefined): string {
  if (!date) return '—';
  return new Date(date).toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function timeAgo(date: string | null | undefined): string {
  if (!date) return '—';
  const diff = Date.now() - new Date(date).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return mins + 'm ago';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + 'h ago';
  const days = Math.floor(hours / 24);
  if (days < 30) return days + 'd ago';
  return formatDate(date);
}

export function truncate(str: string, max: number): string {
  if (str.length <= max) return str;
  return str.slice(0, max) + '...';
}

export function classNames(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(' ');
}
