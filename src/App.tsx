import { useEffect, type ReactNode } from 'react';
import { RouterProvider, useRouter } from '@/lib/router';
import { AuthProvider, useAuth } from '@/lib/auth';
import { ToastProvider } from '@/lib/toast';
import { AppLayout } from '@/components/AppLayout';
import { Spinner } from '@/components/ui';
import { Link } from '@/lib/router';

import { LandingPage } from '@/pages/Landing';
import { LoginPage, RegisterPage, ForgotPasswordPage } from '@/pages/Auth';
import { DashboardPage } from '@/pages/Dashboard';
import { PtcListPage, PtcViewPage } from '@/pages/Ptc';
import { TasksListPage, TaskDetailPage } from '@/pages/Tasks';
import { WalletPage, TransactionsPage, DepositsPage, WithdrawalsPage } from '@/pages/Wallet';
import { ReferralsPage } from '@/pages/Referrals';
import { ProfilePage } from '@/pages/Profile';
import { PublicProfilePage } from '@/pages/PublicProfile';
import { SupportPage } from '@/pages/Support';
import { AdminDashboardPage } from '@/pages/admin/AdminDashboard';
import {
  AdminUsersPage, AdminPtcPage, AdminTasksPage, AdminDepositsPage,
  AdminWithdrawalsPage, AdminTransactionsPage, AdminReferralsPage,
  AdminSupportPage, AdminAuditPage, AdminSettingsPage,
  AdminCampaignsPage, AdminAdvertisersPage, AdminAllCampaignsPage,
} from '@/pages/admin/AdminPages';
import { AdvertiserDashboardPage } from '@/pages/advertiser/AdvertiserDashboard';
import { AdFundPage } from '@/pages/advertiser/AdFund';
import { AdCreatePtcPage } from '@/pages/advertiser/AdCreatePtc';
import { AdCreateTaskPage } from '@/pages/advertiser/AdCreateTask';
import { AdCampaignsPage } from '@/pages/advertiser/AdCampaigns';
import { OffersPage } from '@/pages/Offers';
import { MyOffersPage } from '@/pages/MyOffers';
import { AdminOffersPage } from '@/pages/admin/AdminOffers';

function NotFound() {
  return (
    <div className="min-h-screen bg-ink-950 flex flex-col items-center justify-center gap-4 p-4">
      <div className="w-16 h-16 rounded-2xl brand-gradient flex items-center justify-center">
        <span className="text-ink-950 font-bold text-2xl">G</span>
      </div>
      <h1 className="text-2xl font-bold text-gray-100">Page not found</h1>
      <p className="text-sm text-gray-500">The page you're looking for doesn't exist.</p>
      <Link to="/" className="btn-primary">Go Home</Link>
    </div>
  );
}

function ProtectedRoute({ children }: { children: ReactNode }) {
  const { profile, loading } = useAuth();
  const { navigate } = useRouter();

  useEffect(() => {
    if (!loading && !profile) navigate('/login');
  }, [loading, profile, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen bg-ink-950 flex items-center justify-center">
        <Spinner size={32} />
      </div>
    );
  }
  if (!profile) return null;
  return <AppLayout>{children}</AppLayout>;
}

function AdminRoute({ children }: { children: ReactNode }) {
  const { profile, loading } = useAuth();
  const { navigate } = useRouter();

  useEffect(() => {
    if (!loading && !profile) navigate('/login');
    else if (!loading && profile && profile.role !== 'admin') navigate('/dashboard');
  }, [loading, profile, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen bg-ink-950 flex items-center justify-center">
        <Spinner size={32} />
      </div>
    );
  }
  if (!profile || profile.role !== 'admin') return null;
  return <AppLayout>{children}</AppLayout>;
}

function PublicOnlyRoute({ children }: { children: ReactNode }) {
  const { profile, loading } = useAuth();
  const { navigate } = useRouter();

  useEffect(() => {
    if (!loading && profile) navigate('/dashboard');
  }, [loading, profile, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen bg-ink-950 flex items-center justify-center">
        <Spinner size={32} />
      </div>
    );
  }
  if (profile) return null;
  return <>{children}</>;
}

function AppRoutes() {
  const { path } = useRouter();

  // Dynamic route matching
  const ptcMatch = path.match(/^\/ptc\/(.+)$/);
  const taskMatch = path.match(/^\/tasks\/(.+)$/);
  const publicProfileMatch = path.match(/^\/profile\/(.+)$/);

  // Public routes
  if (path === '/') return <LandingPage />;
  if (path === '/login') return <PublicOnlyRoute><LoginPage /></PublicOnlyRoute>;
  if (path === '/register') return <PublicOnlyRoute><RegisterPage /></PublicOnlyRoute>;
  if (path === '/forgot-password') return <PublicOnlyRoute><ForgotPasswordPage /></PublicOnlyRoute>;

  // Protected user routes
  if (path === '/dashboard') return <ProtectedRoute><DashboardPage /></ProtectedRoute>;
  if (path === '/ptc') return <ProtectedRoute><PtcListPage /></ProtectedRoute>;
  if (ptcMatch) return <ProtectedRoute><PtcViewPage adId={ptcMatch[1]} /></ProtectedRoute>;
  if (path === '/tasks') return <ProtectedRoute><TasksListPage /></ProtectedRoute>;
  if (taskMatch) return <ProtectedRoute><TaskDetailPage taskId={taskMatch[1]} /></ProtectedRoute>;
  if (path === '/wallet') return <ProtectedRoute><WalletPage /></ProtectedRoute>;
  if (path === '/transactions') return <ProtectedRoute><TransactionsPage /></ProtectedRoute>;
  if (path === '/deposits') return <ProtectedRoute><DepositsPage /></ProtectedRoute>;
  if (path === '/withdrawals') return <ProtectedRoute><WithdrawalsPage /></ProtectedRoute>;
  if (path === '/referrals') return <ProtectedRoute><ReferralsPage /></ProtectedRoute>;
  if (path === '/offers') return <ProtectedRoute><OffersPage /></ProtectedRoute>;
  if (path === '/my-offers') return <ProtectedRoute><MyOffersPage /></ProtectedRoute>;
  if (path === '/profile') return <ProtectedRoute><ProfilePage /></ProtectedRoute>;
  if (publicProfileMatch) return <ProtectedRoute><PublicProfilePage username={publicProfileMatch[1]} /></ProtectedRoute>;
  if (path === '/support') return <ProtectedRoute><SupportPage /></ProtectedRoute>;

  // Advertiser routes
  if (path === '/advertiser') return <ProtectedRoute><AdvertiserDashboardPage /></ProtectedRoute>;
  if (path === '/advertiser/fund') return <ProtectedRoute><AdFundPage /></ProtectedRoute>;
  if (path === '/advertiser/create-ptc') return <ProtectedRoute><AdCreatePtcPage /></ProtectedRoute>;
  if (path === '/advertiser/create-task') return <ProtectedRoute><AdCreateTaskPage /></ProtectedRoute>;
  if (path === '/advertiser/campaigns') return <ProtectedRoute><AdCampaignsPage /></ProtectedRoute>;

  // Admin routes
  if (path === '/admin') return <AdminRoute><AdminDashboardPage /></AdminRoute>;
  if (path === '/admin/users') return <AdminRoute><AdminUsersPage /></AdminRoute>;
  if (path === '/admin/ptc') return <AdminRoute><AdminPtcPage /></AdminRoute>;
  if (path === '/admin/tasks') return <AdminRoute><AdminTasksPage /></AdminRoute>;
  if (path === '/admin/campaigns') return <AdminRoute><AdminCampaignsPage /></AdminRoute>;
  if (path === '/admin/advertisers') return <AdminRoute><AdminAdvertisersPage /></AdminRoute>;
  if (path === '/admin/all-campaigns') return <AdminRoute><AdminAllCampaignsPage /></AdminRoute>;
  if (path === '/admin/deposits') return <AdminRoute><AdminDepositsPage /></AdminRoute>;
  if (path === '/admin/withdrawals') return <AdminRoute><AdminWithdrawalsPage /></AdminRoute>;
  if (path === '/admin/transactions') return <AdminRoute><AdminTransactionsPage /></AdminRoute>;
  if (path === '/admin/referrals') return <AdminRoute><AdminReferralsPage /></AdminRoute>;
  if (path === '/admin/support') return <AdminRoute><AdminSupportPage /></AdminRoute>;
  if (path === '/admin/audit') return <AdminRoute><AdminAuditPage /></AdminRoute>;
  if (path === '/admin/settings') return <AdminRoute><AdminSettingsPage /></AdminRoute>;
  if (path === '/admin/offers') return <AdminRoute><AdminOffersPage /></AdminRoute>;

  return <NotFound />;
}

export default function App() {
  return (
    <RouterProvider>
      <AuthProvider>
        <ToastProvider>
          <AppRoutes />
        </ToastProvider>
      </AuthProvider>
    </RouterProvider>
  );
}
