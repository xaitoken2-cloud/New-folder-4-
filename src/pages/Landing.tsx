import { Link } from '@/lib/router';
import {
  MousePointerClick, ListChecks, Users, Shield, Zap,
  TrendingUp, ArrowRight, CheckCircle2, Lock,
} from 'lucide-react';

export function LandingPage() {
  return (
    <div className="min-h-screen bg-ink-950">
      {/* Nav */}
      <nav className="sticky top-0 z-40 bg-ink-950/80 backdrop-blur border-b border-ink-800">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center">
              <span className="text-ink-950 font-bold text-lg">G</span>
            </div>
            <span className="font-bold text-gray-100 text-lg">GoldClicks</span>
          </div>
          <div className="flex items-center gap-2 sm:gap-4">
            <Link to="/login" className="btn-ghost text-sm">Sign In</Link>
            <Link to="/register" className="btn-primary text-sm">Get Started</Link>
          </div>
        </div>
      </nav>

      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-brand-500/5 via-transparent to-transparent" />
        <div className="absolute top-20 left-1/2 -translate-x-1/2 w-[600px] h-[600px] bg-brand-500/10 rounded-full blur-[120px]" />
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 pt-20 pb-24 text-center">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-brand-500/10 border border-brand-500/20 text-brand-400 text-xs font-medium mb-6 animate-fade-in">
            <Zap size={12} /> Earn real rewards for your attention
          </div>
          <h1 className="text-4xl sm:text-6xl font-bold text-gray-100 mb-5 leading-tight animate-slide-up">
            Turn your clicks into <span className="brand-text">rewards</span>
          </h1>
          <p className="text-lg text-gray-400 max-w-2xl mx-auto mb-8 animate-slide-up">
            GoldClicks is a premium paid-to-click platform where you earn real money by viewing ads,
            completing tasks, and referring friends. Server-verified rewards, transparent ledger,
            instant withdrawals.
          </p>
          <div className="flex items-center justify-center gap-3 mb-12 animate-slide-up">
            <Link to="/register" className="btn-primary text-base px-6 py-3">
              Start Earning <ArrowRight size={18} />
            </Link>
            <Link to="/login" className="btn-secondary text-base px-6 py-3">
              Sign In
            </Link>
          </div>

          {/* Stats bar */}
          <div className="grid grid-cols-3 gap-4 max-w-2xl mx-auto">
            {[
              { value: '6+', label: 'Active Ads' },
              { value: '5+', label: 'Tasks Available' },
              { value: '100%', label: 'Server-Verified' },
            ].map((s) => (
              <div key={s.label} className="card p-4">
                <div className="text-2xl font-bold brand-text">{s.value}</div>
                <div className="text-xs text-gray-500 mt-1">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-16">
        <h2 className="text-2xl sm:text-3xl font-bold text-gray-100 text-center mb-3">How it works</h2>
        <p className="text-gray-500 text-center mb-12 max-w-xl mx-auto">
          Three simple ways to earn. All rewards are verified and recorded on our server — never faked.
        </p>
        <div className="grid sm:grid-cols-3 gap-5">
          {[
            { icon: <MousePointerClick size={24} />, title: 'View Ads', desc: 'Watch advertisements for a set duration. The server verifies your view time before crediting your reward.' },
            { icon: <ListChecks size={24} />, title: 'Complete Tasks', desc: 'Visit websites, follow social accounts, take surveys, and more. Submit proof and get rewarded.' },
            { icon: <Users size={24} />, title: 'Refer Friends', desc: 'Share your referral link and earn commission when your referrals start earning on the platform.' },
          ].map((f) => (
            <div key={f.title} className="card card-hover p-6">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 text-brand-400 flex items-center justify-center mb-4">
                {f.icon}
              </div>
              <h3 className="text-base font-semibold text-gray-100 mb-2">{f.title}</h3>
              <p className="text-sm text-gray-500 leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Trust section */}
      <section className="bg-ink-900 border-y border-ink-800 py-16">
        <div className="max-w-6xl mx-auto px-4 sm:px-6">
          <div className="grid sm:grid-cols-2 gap-8 items-center">
            <div>
              <div className="inline-flex items-center gap-2 text-brand-400 text-sm font-medium mb-4">
                <Shield size={16} /> Security First
              </div>
              <h2 className="text-2xl font-bold text-gray-100 mb-4">Your earnings are protected</h2>
              <p className="text-gray-500 mb-6">
                Every reward is validated server-side. We use database transactions, row-level security,
                and server-side timers to ensure fairness. No browser tricks, no fake balances.
              </p>
              <div className="space-y-3">
                {[
                  'Server-verified PTC view timers',
                  'Transactional financial ledger',
                  'Row-level security on all tables',
                  'Admin authorization enforced server-side',
                ].map((item) => (
                  <div key={item} className="flex items-center gap-2.5 text-sm text-gray-300">
                    <CheckCircle2 size={16} className="text-success-500 shrink-0" />
                    {item}
                  </div>
                ))}
              </div>
            </div>
            <div className="card p-6">
              <div className="flex items-center justify-between mb-4">
                <span className="text-xs text-gray-500 uppercase tracking-wide">Earnings Preview</span>
                <TrendingUp size={16} className="text-success-500" />
              </div>
              <div className="space-y-3">
                {[
                  { label: 'Available Balance', value: '$12.4500', color: 'text-brand-400' },
                  { label: 'Today\'s Earnings', value: '$0.0325', color: 'text-success-500' },
                  { label: 'Total Earned', value: '$48.7200', color: 'text-gray-200' },
                  { label: 'Referral Earnings', value: '$3.5000', color: 'text-blue-400' },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between py-2 border-b border-ink-700 last:border-0">
                    <span className="text-sm text-gray-400">{row.label}</span>
                    <span className={`font-mono font-semibold ${row.color}`}>{row.value}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="max-w-4xl mx-auto px-4 sm:px-6 py-20 text-center">
        <div className="inline-flex items-center gap-2 text-brand-400 mb-4">
          <Lock size={16} />
        </div>
        <h2 className="text-3xl font-bold text-gray-100 mb-4">Ready to start earning?</h2>
        <p className="text-gray-500 mb-8 max-w-xl mx-auto">
          Create your free account in seconds. No fees, no hidden charges. Just real rewards for your attention.
        </p>
        <Link to="/register" className="btn-primary text-base px-8 py-3.5 inline-flex">
          Create Free Account <ArrowRight size={18} />
        </Link>
      </section>

      {/* Footer */}
      <footer className="border-t border-ink-800 py-8">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg brand-gradient flex items-center justify-center">
              <span className="text-ink-950 font-bold text-sm">G</span>
            </div>
            <span className="text-sm text-gray-500">GoldClicks &copy; 2026</span>
          </div>
          <div className="flex items-center gap-6 text-sm text-gray-500">
            <Link to="/login" className="hover:text-gray-300">Sign In</Link>
            <Link to="/register" className="hover:text-gray-300">Register</Link>
            <Link to="/login" className="hover:text-gray-300">Support</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
