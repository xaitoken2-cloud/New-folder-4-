import { useState, useEffect, type ReactNode } from 'react';
import { Link, useRouter } from '@/lib/router';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import {
  LayoutDashboard, MousePointerClick, ListChecks, Wallet, ArrowDownToLine,
  ArrowUpFromLine, Users, Ticket, User, Menu, LogOut, Shield,
  ScrollText, Settings, BarChart3, FileText, ChevronRight, Megaphone, TrendingUp,
  Gift, History,
} from 'lucide-react';
import { classNames } from '@/lib/format';

interface NavItem {
  label: string;
  to: string;
  icon: ReactNode;
}

const userNav: NavItem[] = [
  { label: 'Dashboard', to: '/dashboard', icon: <LayoutDashboard size={18} /> },
  { label: 'PTC Ads', to: '/ptc', icon: <MousePointerClick size={18} /> },
  { label: 'Offers', to: '/offers', icon: <Gift size={18} /> },
  { label: 'My Offers', to: '/my-offers', icon: <History size={18} /> },
  { label: 'Tasks', to: '/tasks', icon: <ListChecks size={18} /> },
  { label: 'Wallet', to: '/wallet', icon: <Wallet size={18} /> },
  { label: 'History', to: '/transactions', icon: <ScrollText size={18} /> },
  { label: 'Withdrawals', to: '/withdrawals', icon: <ArrowUpFromLine size={18} /> },
  { label: 'Referrals', to: '/referrals', icon: <Users size={18} /> },
  { label: 'Support', to: '/support', icon: <Ticket size={18} /> },
  { label: 'Profile', to: '/profile', icon: <User size={18} /> },
];

const advertiserNav: NavItem[] = [
  { label: 'Advertiser', to: '/advertiser', icon: <Megaphone size={18} /> },
  { label: 'My Campaigns', to: '/advertiser/campaigns', icon: <ListChecks size={18} /> },
  { label: 'Deposits', to: '/deposits', icon: <ArrowDownToLine size={18} /> },
  { label: 'Create PTC Ad', to: '/advertiser/create-ptc', icon: <MousePointerClick size={18} /> },
  { label: 'Create Task', to: '/advertiser/create-task', icon: <ListChecks size={18} /> },
];

const adminNav: NavItem[] = [
  { label: 'Admin Dashboard', to: '/admin', icon: <BarChart3 size={18} /> },
  { label: 'Users', to: '/admin/users', icon: <Users size={18} /> },
  { label: 'PTC Management', to: '/admin/ptc', icon: <MousePointerClick size={18} /> },
  { label: 'Task Management', to: '/admin/tasks', icon: <ListChecks size={18} /> },
  { label: 'Campaign Approvals', to: '/admin/campaigns', icon: <Megaphone size={18} /> },
  { label: 'All Campaigns', to: '/admin/all-campaigns', icon: <TrendingUp size={18} /> },
  { label: 'Advertisers', to: '/admin/advertisers', icon: <Shield size={18} /> },
  { label: 'Deposits', to: '/admin/deposits', icon: <ArrowDownToLine size={18} /> },
  { label: 'Withdrawals', to: '/admin/withdrawals', icon: <ArrowUpFromLine size={18} /> },
  { label: 'Transactions', to: '/admin/transactions', icon: <ScrollText size={18} /> },
  { label: 'Referrals', to: '/admin/referrals', icon: <Users size={18} /> },
  { label: 'Support', to: '/admin/support', icon: <Ticket size={18} /> },
  { label: 'Audit Logs', to: '/admin/audit', icon: <FileText size={18} /> },
  { label: 'Offers', to: '/admin/offers', icon: <Gift size={18} /> },
  { label: 'Settings', to: '/admin/settings', icon: <Settings size={18} /> },
];

export function AppLayout({ children }: { children: ReactNode }) {
  const { profile, signOut, impersonation, returnToAdmin } = useAuth();
  const { path, navigate } = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);

  const isAdmin = profile?.role === 'admin';
  const nav = isAdmin ? [...adminNav, ...advertiserNav, ...userNav] : [...advertiserNav, ...userNav];

  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMobileOpen(false);
    };
    document.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [mobileOpen]);

  const isActive = (to: string) => {
    if (to === '/dashboard' && path === '/dashboard') return true;
    if (to === '/admin' && path === '/admin') return true;
    return path.startsWith(to) && to !== '/dashboard' && to !== '/admin';
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-ink-950 flex">
      {/* Desktop sidebar */}
      <aside className="hidden lg:flex w-64 flex-col bg-ink-900 border-r border-ink-800 fixed h-full z-30">
        <SidebarContent
          nav={nav}
          isAdmin={isAdmin}
          profile={profile}
          isActive={isActive}
          onSignOut={handleSignOut}
        />
      </aside>

      {/* Mobile sidebar drawer */}
      <div className={classNames(
        'lg:hidden fixed inset-0 z-50 transition-opacity duration-300',
        mobileOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'
      )}>
        <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setMobileOpen(false)} />
        <aside className={classNames(
          'relative w-72 max-w-[85vw] flex flex-col bg-ink-900 border-r border-ink-800 h-full transition-transform duration-300 ease-out',
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        )}>
          <SidebarContent
            nav={nav}
            isAdmin={isAdmin}
            profile={profile}
            isActive={isActive}
            onSignOut={handleSignOut}
            onNavigate={() => setMobileOpen(false)}
          />
        </aside>
      </div>

      {/* Main content */}
      <div className="flex-1 lg:ml-64 flex flex-col min-h-screen">
        {impersonation && (
          <div className="sticky top-0 z-40 bg-brand-500/95 text-white px-4 py-2.5 flex items-center justify-between gap-3 shadow-lg">
            <div className="flex items-center gap-2 text-sm font-medium">
              <Shield size={16} />
              <span>Admin Mode — Viewing as {impersonation.impersonatedUsername}</span>
            </div>
            <button
              onClick={async () => { await returnToAdmin(); navigate('/admin/users'); }}
              className="bg-ink-950 text-brand-400 px-3 py-1 rounded-lg text-xs font-semibold hover:bg-ink-900 transition-colors"
            >
              Return to Admin
            </button>
          </div>
        )}
        {/* Mobile header */}
        <header className="lg:hidden sticky top-0 z-20 bg-ink-900/90 backdrop-blur border-b border-ink-800 px-4 py-3 flex items-center justify-between">
          <button onClick={() => setMobileOpen(true)} className="w-10 h-10 -ml-1 flex items-center justify-center rounded-lg text-gray-400 hover:text-gray-100 hover:bg-ink-800 transition-colors" aria-label="Open menu">
            <Menu size={22} />
          </button>
          <Link to="/dashboard" className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg brand-gradient flex items-center justify-center">
              <span className="text-ink-950 font-bold text-sm">G</span>
            </div>
            <span className="font-bold text-gray-100">GoldClicks</span>
          </Link>
          <div className="w-10 h-10 flex items-center justify-center rounded-full bg-ink-700 text-brand-400 font-semibold text-sm shrink-0">
            {profile?.username?.charAt(0).toUpperCase() ?? '?'}
          </div>
        </header>

        <main className="flex-1 p-4 lg:p-8 max-w-7xl mx-auto w-full">{children}</main>
      </div>
    </div>
  );
}

function SidebarContent({
  nav,
  isAdmin,
  profile,
  isActive,
  onSignOut,
  onNavigate,
}: {
  nav: NavItem[];
  isAdmin: boolean;
  profile: ReturnType<typeof useAuth>['profile'];
  isActive: (to: string) => boolean;
  onSignOut: () => void;
  onNavigate?: () => void;
}) {
  return (
    <>
      <div className="px-5 py-5 border-b border-ink-800">
        <Link to="/dashboard" className="flex items-center gap-2.5" onClick={onNavigate}>
          <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center shadow-lg shadow-brand-500/20">
            <span className="text-ink-950 font-bold text-lg">G</span>
          </div>
          <div>
            <span className="font-bold text-gray-100 text-base">GoldClicks</span>
            <span className="block text-[10px] text-brand-500/70 font-medium tracking-wider uppercase">PTC Platform</span>
          </div>
        </Link>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-1">
        {isAdmin && (
          <div className="px-3 mb-2">
            <span className="text-[10px] font-semibold text-brand-500/60 uppercase tracking-wider flex items-center gap-1.5">
              <Shield size={11} /> Admin Panel
            </span>
          </div>
        )}
        {nav.map((item, i) => {
          const adminLen = adminNav.length;
          const adLen = advertiserNav.length;
          const showAdminDivider = isAdmin && i === adminLen;
          const showAdDivider = (isAdmin && i === adminLen + adLen) || (!isAdmin && i === adLen);
          return (
            <div key={item.to}>
              {showAdminDivider && (
                <div className="px-3 mt-4 mb-2">
                  <span className="text-[10px] font-semibold text-brand-500/60 uppercase tracking-wider">Advertiser Panel</span>
                </div>
              )}
              {showAdDivider && (
                <div className="px-3 mt-4 mb-2">
                  <span className="text-[10px] font-semibold text-gray-500 uppercase tracking-wider">User Panel</span>
                </div>
              )}
              <Link
                to={item.to}
                onClick={onNavigate}
                className={classNames(isActive(item.to) ? 'nav-link-active' : 'nav-link')}
              >
                {item.icon}
                <span>{item.label}</span>
                {isActive(item.to) && <ChevronRight size={14} className="ml-auto" />}
              </Link>
            </div>
          );
        })}
      </nav>

      <div className="px-3 py-4 border-t border-ink-800">
        <div className="flex items-center gap-3 px-2 mb-3">
          <div className="w-9 h-9 rounded-full bg-ink-700 flex items-center justify-center text-brand-400 font-semibold text-sm">
            {profile?.username?.charAt(0).toUpperCase() ?? '?'}
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-sm font-medium text-gray-200 truncate">{profile?.username}</div>
            <div className="text-xs text-gray-500 truncate">{profile?.email}</div>
          </div>
        </div>
        <button onClick={onSignOut} className="nav-link w-full text-danger-500 hover:text-danger-400 hover:bg-danger-500/5">
          <LogOut size={18} />
          <span>Sign Out</span>
        </button>
      </div>
    </>
  );
}

export { supabase };
