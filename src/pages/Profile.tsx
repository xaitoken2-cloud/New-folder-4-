import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth';
import { updateProfile, getSettings, changePassword, getErrorMessage } from '@/lib/api';
import { COUNTRY_NAME_MAP } from '@/lib/countries';
import { supabase } from '@/lib/supabase';
import { useToast } from '@/lib/toast';
import { LoadingScreen, PageHeader, Badge } from '@/components/ui';
import { formatDate } from '@/lib/format';
import { User, Mail, MapPin, Shield, Calendar, Save, Lock, Eye, EyeOff, AlertCircle, CheckCircle2 } from 'lucide-react';
import type { AppSettings } from '@/types';

export function ProfilePage() {
  const { profile, refreshProfile } = useAuth();
  const { toast } = useToast();
  const [fullName, setFullName] = useState('');
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState<AppSettings | null>(null);

  const [pwForm, setPwForm] = useState({ current: '', next: '', confirm: '' });
  const [showPw, setShowPw] = useState(false);
  const [changingPw, setChangingPw] = useState(false);
  const [pwError, setPwError] = useState('');
  const [pwSuccess, setPwSuccess] = useState(false);

  useEffect(() => {
    if (profile) {
      setFullName(profile.full_name);
    }
  }, [profile]);

  useEffect(() => {
    getSettings().then(setSettings).catch(() => {});
  }, []);

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setPwError('');
    setPwSuccess(false);

    if (pwForm.next.length < 6) {
      setPwError('Password must be at least 6 characters');
      return;
    }
    if (pwForm.next !== pwForm.confirm) {
      setPwError('New passwords do not match');
      return;
    }

    setChangingPw(true);
    try {
      await changePassword(pwForm.current, pwForm.next);
      setPwSuccess(true);
      setPwForm({ current: '', next: '', confirm: '' });
      toast('Password changed successfully. Please log in again.', 'success');
      setTimeout(() => {
        supabase.auth.signOut();
      }, 2000);
    } catch (err) {
      setPwError(getErrorMessage(err, 'Failed to change password'));
    } finally {
      setChangingPw(false);
    }
  };

  if (!profile) return <LoadingScreen />;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await updateProfile({ full_name: fullName });
      await refreshProfile();
      toast('Profile updated successfully', 'success');
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to update profile'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <PageHeader title="Profile" subtitle="Manage your account information" />

      <div className="grid lg:grid-cols-3 gap-6">
        {/* Profile card */}
        <div className="card p-6">
          <div className="flex flex-col items-center text-center mb-6">
            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-brand-500/20 to-brand-700/20 flex items-center justify-center text-brand-400 font-bold text-2xl mb-3">
              {profile.username.charAt(0).toUpperCase()}
            </div>
            <h2 className="text-base font-semibold text-gray-100">{profile.username}</h2>
            <p className="text-sm text-gray-500">{profile.email}</p>
            <div className="flex items-center gap-2 mt-3">
              <Badge variant={profile.role === 'admin' ? 'brand' : 'neutral'}>
                {profile.role}
              </Badge>
              <Badge variant={profile.status === 'active' ? 'success' : 'danger'}>
                {profile.status}
              </Badge>
            </div>
          </div>

          <div className="space-y-3 text-sm">
            <div className="flex items-center gap-2 text-gray-400">
              <Calendar size={14} className="text-gray-500" /> Joined {formatDate(profile.created_at)}
            </div>
            <div className="flex items-center gap-2 text-gray-400">
              <Shield size={14} className="text-gray-500" /> Referral code: <span className="font-mono text-brand-400">{profile.referral_code}</span>
            </div>
            {profile.referred_by && (
              <div className="flex items-center gap-2 text-gray-400">
                <User size={14} className="text-gray-500" /> Referred by another user
              </div>
            )}
          </div>
        </div>

        {/* Edit form */}
        <div className="card p-6 lg:col-span-2">
          <h3 className="text-sm font-semibold text-gray-200 mb-5">Edit Profile</h3>
          <form onSubmit={handleSave} className="space-y-4 max-w-md">
            <div>
              <label className="label">Full Name</label>
              <div className="relative">
                <User size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
                <input value={fullName} onChange={(e) => setFullName(e.target.value)} className="input pl-10" />
              </div>
            </div>
            <div>
              <label className="label">Email (read-only)</label>
              <div className="relative">
                <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
                <input value={profile.email} disabled className="input pl-10 opacity-60" />
              </div>
            </div>
            <div>
              <label className="label">Country</label>
              <div className="relative">
                <MapPin size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
                <input
                  value={profile.country ? (COUNTRY_NAME_MAP[profile.country] ?? profile.country) : 'Not detected'}
                  disabled
                  className="input pl-10 opacity-60"
                />
              </div>
              <p className="text-xs text-gray-500 mt-1.5">Detected automatically</p>
            </div>
            <button type="submit" disabled={saving} className="btn-primary">
              {saving ? 'Saving...' : <><Save size={16} /> Save Changes</>}
            </button>
          </form>

          {settings && (
            <div className="mt-8 pt-6 border-t border-ink-700">
              <h3 className="text-sm font-semibold text-gray-200 mb-3">Account Stats</h3>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                <div className="p-3 rounded-lg bg-ink-800">
                  <div className="text-xs text-gray-500">PTC Views</div>
                  <div className="text-lg font-mono font-bold text-gray-200">{profile.ptc_views}</div>
                </div>
                <div className="p-3 rounded-lg bg-ink-800">
                  <div className="text-xs text-gray-500">Tasks Done</div>
                  <div className="text-lg font-mono font-bold text-gray-200">{profile.tasks_completed}</div>
                </div>
                <div className="p-3 rounded-lg bg-ink-800">
                  <div className="text-xs text-gray-500">Min Withdrawal</div>
                  <div className="text-lg font-mono font-bold text-gray-200">${settings.min_withdrawal}</div>
                </div>
                <div className="p-3 rounded-lg bg-ink-800">
                  <div className="text-xs text-gray-500">Referral Commission</div>
                  <div className="text-lg font-mono font-bold text-brand-400">{settings.referral_commission_percent}%</div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Change Password */}
      <div className="card p-6 mt-6 max-w-md">
        <div className="flex items-center gap-2 mb-5">
          <Lock size={16} className="text-brand-400" />
          <h3 className="text-sm font-semibold text-gray-200">Change Password</h3>
        </div>
        <form onSubmit={handlePasswordChange} className="space-y-4">
          {pwError && (
            <div className="flex items-start gap-2 px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm">
              <AlertCircle size={16} className="shrink-0 mt-0.5" />
              <span>{pwError}</span>
            </div>
          )}
          {pwSuccess && (
            <div className="flex items-start gap-2 px-3.5 py-3 rounded-lg bg-success-500/10 border border-success-500/20 text-success-500 text-sm">
              <CheckCircle2 size={16} className="shrink-0 mt-0.5" />
              <span>Password changed. You will be signed out shortly.</span>
            </div>
          )}
          <div>
            <label className="label">Current Password</label>
            <div className="relative">
              <input
                type={showPw ? 'text' : 'password'}
                required
                value={pwForm.current}
                onChange={(e) => setPwForm({ ...pwForm, current: e.target.value })}
                className="input pr-10"
                autoComplete="current-password"
              />
              <button type="button" onClick={() => setShowPw(!showPw)} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300">
                {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          <div>
            <label className="label">New Password</label>
            <input
              type={showPw ? 'text' : 'password'}
              required
              value={pwForm.next}
              onChange={(e) => setPwForm({ ...pwForm, next: e.target.value })}
              className="input"
              placeholder="Min 6 characters"
              autoComplete="new-password"
            />
          </div>
          <div>
            <label className="label">Confirm New Password</label>
            <input
              type={showPw ? 'text' : 'password'}
              required
              value={pwForm.confirm}
              onChange={(e) => setPwForm({ ...pwForm, confirm: e.target.value })}
              className="input"
              autoComplete="new-password"
            />
          </div>
          <button type="submit" disabled={changingPw} className="btn-primary">
            {changingPw ? 'Changing...' : <><Lock size={16} /> Change Password</>}
          </button>
        </form>
      </div>
    </div>
  );
}
