import { useEffect, useState } from 'react';
import { Link, useRouter, getHashQueryParam } from '@/lib/router';
import { detectUserCountry, getErrorMessage } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { Spinner } from '@/components/ui';
import { Mail, Lock, Eye, EyeOff, AlertCircle } from 'lucide-react';

export function LoginPage() {
  const { signIn } = useAuth();
  const { navigate } = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await signIn(email, password);
      navigate('/dashboard');
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to sign in'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell title="Welcome back" subtitle="Sign in to your GoldClicks account">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="flex items-start gap-2 px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm">
            <AlertCircle size={16} className="shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}
        <div>
          <label className="label">Email Address</label>
          <div className="relative">
            <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="input pl-10"
            />
          </div>
        </div>
        <div>
          <label className="label">Password</label>
          <div className="relative">
            <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
            <input
              type={showPassword ? 'text' : 'password'}
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password"
              className="input pl-10 pr-10"
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
            >
              {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
            </button>
          </div>
        </div>
        <button type="submit" disabled={loading} className="btn-primary w-full">
          {loading ? <Spinner size={18} /> : 'Sign In'}
        </button>
      </form>
      <div className="mt-6 text-center text-sm text-gray-500">
        <Link to="/forgot-password" className="text-brand-400 hover:text-brand-300">
          Forgot your password?
        </Link>
      </div>
      <div className="mt-4 text-center text-sm text-gray-500">
        Don't have an account?{' '}
        <Link to="/register" className="text-brand-400 hover:text-brand-300 font-medium">
          Sign up
        </Link>
      </div>
    </AuthShell>
  );
}

export function RegisterPage() {
  const { signUp } = useAuth();
  const [form, setForm] = useState({
    username: '',
    fullName: '',
    email: '',
    confirmEmail: '',
    password: '',
    confirmPassword: '',
  });
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [referralCode, setReferralCode] = useState('');

  useEffect(() => {
    const ref = getHashQueryParam('ref');
    if (ref) setReferralCode(ref);
  }, []);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((prev) => ({ ...prev, [key]: e.target.value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (form.email !== form.confirmEmail) {
      setError('Emails do not match');
      return;
    }
    if (form.password !== form.confirmPassword) {
      setError('Passwords do not match');
      return;
    }
    if (form.password.length < 6) {
      setError('Password must be at least 6 characters');
      return;
    }

    setLoading(true);
    try {
      await signUp({
        email: form.email,
        password: form.password,
        username: form.username,
        fullName: form.fullName,
        referralCode,
      });
      setSuccess(true);
      detectUserCountry().catch(() => {});
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to create account'));
    } finally {
      setLoading(false);
    }
  };

  if (success) {
    return (
      <AuthShell title="Account created" subtitle="Your GoldClicks account is ready">
        <div className="text-center py-4">
          <div className="w-14 h-14 rounded-full bg-success-500/10 flex items-center justify-center mx-auto mb-4 text-success-500 text-2xl">
            ✓
          </div>
          <p className="text-sm text-gray-400 mb-6">
            Your account has been created successfully. You can now sign in with your credentials.
          </p>
          <Link to="/login" className="btn-primary inline-flex">
            Go to Sign In
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title="Create your account" subtitle="Start earning in less than a minute">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="flex items-start gap-2 px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm">
            <AlertCircle size={16} className="shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="label">Username</label>
            <input required value={form.username} onChange={set('username')} placeholder="golduser" className="input" />
          </div>
          <div>
            <label className="label">Full Name</label>
            <input required value={form.fullName} onChange={set('fullName')} placeholder="John Doe" className="input" />
          </div>
        </div>
        <div>
          <label className="label">Email Address</label>
          <input type="email" required value={form.email} onChange={set('email')} placeholder="you@example.com" className="input" />
        </div>
        <div>
          <label className="label">Confirm Email</label>
          <input type="email" required value={form.confirmEmail} onChange={set('confirmEmail')} placeholder="you@example.com" className="input" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="label">Password</label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                required
                value={form.password}
                onChange={set('password')}
                placeholder="Min 6 characters"
                className="input pr-10"
              />
              <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300">
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          <div>
            <label className="label">Confirm</label>
            <input
              type={showPassword ? 'text' : 'password'}
              required
              value={form.confirmPassword}
              onChange={set('confirmPassword')}
              placeholder="Repeat password"
              className="input"
            />
          </div>
        </div>
        <button type="submit" disabled={loading} className="btn-primary w-full">
          {loading ? <Spinner size={18} /> : 'Create Account'}
        </button>
      </form>
      <div className="mt-6 text-center text-sm text-gray-500">
        Already have an account?{' '}
        <Link to="/login" className="text-brand-400 hover:text-brand-300 font-medium">
          Sign in
        </Link>
      </div>
    </AuthShell>
  );
}

export function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { requestPasswordReset } = await import('@/lib/api');
      await requestPasswordReset(email);
      setSent(true);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to send reset email'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell title="Reset password" subtitle="We'll send you a recovery link">
      {sent ? (
        <div className="text-center py-4">
          <div className="w-14 h-14 rounded-full bg-success-500/10 flex items-center justify-center mx-auto mb-4 text-success-500 text-2xl">
            ✓
          </div>
          <p className="text-sm text-gray-400 mb-6">
            If that email is registered, a password reset link has been sent. Check your inbox.
          </p>
          <Link to="/login" className="btn-primary inline-flex">
            Back to Sign In
          </Link>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-start gap-2 px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm">
              <AlertCircle size={16} className="shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
          <div>
            <label className="label">Email Address</label>
            <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" className="input" />
          </div>
          <button type="submit" disabled={loading} className="btn-primary w-full">
            {loading ? <Spinner size={18} /> : 'Send Reset Link'}
          </button>
        </form>
      )}
      <div className="mt-6 text-center text-sm text-gray-500">
        <Link to="/login" className="text-brand-400 hover:text-brand-300">
          Back to sign in
        </Link>
      </div>
    </AuthShell>
  );
}

function AuthShell({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-ink-950 flex flex-col">
      <nav className="px-4 sm:px-6 h-16 flex items-center justify-between border-b border-ink-800">
        <Link to="/" className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center">
            <span className="text-ink-950 font-bold text-lg">G</span>
          </div>
          <span className="font-bold text-gray-100 text-lg">GoldClicks</span>
        </Link>
        <Link to="/" className="text-sm text-gray-500 hover:text-gray-300">
          Home
        </Link>
      </nav>
      <div className="flex-1 flex items-center justify-center p-4">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[500px] h-[500px] bg-brand-500/5 rounded-full blur-[100px] pointer-events-none" />
        <div className="relative w-full max-w-md card p-6 sm:p-8 animate-slide-up">
          <h1 className="text-xl font-bold text-gray-100 mb-1">{title}</h1>
          <p className="text-sm text-gray-500 mb-6">{subtitle}</p>
          {children}
        </div>
      </div>
    </div>
  );
}
