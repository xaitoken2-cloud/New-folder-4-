import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';
import { supabase } from './supabase';
import { getProfile, signIn, signOut as apiSignOut, signUp, detectUserCountry, type SignUpInput } from './api';
import type { Profile } from '@/types';

interface ImpersonationState {
  adminAccessToken: string;
  adminRefreshToken: string;
  adminUserId: string;
  impersonatedUserId: string;
  impersonatedUsername: string;
}

interface AuthContextValue {
  profile: Profile | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (input: SignUpInput) => Promise<void>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
  impersonation: ImpersonationState | null;
  impersonateUser: (targetUserId: string, targetUsername: string, accessToken: string, refreshToken: string) => Promise<void>;
  returnToAdmin: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

const STORAGE_KEY = 'admin_impersonation';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [impersonation, setImpersonation] = useState<ImpersonationState | null>(null);

  const refreshProfile = useCallback(async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        setProfile(null);
        return;
      }
      const p = await getProfile();
      setProfile(p);
    } catch {
      setProfile(null);
    }
  }, []);

  useEffect(() => {
    let mounted = true;

    (async () => {
      await refreshProfile();
      if (mounted) setLoading(false);
    })();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      (async () => {
        await refreshProfile();
      })();
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, [refreshProfile]);

  // Restore impersonation state from storage on mount
  useEffect(() => {
    try {
      const stored = sessionStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as ImpersonationState;
        setImpersonation(parsed);
      }
    } catch {
      sessionStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  const handleSignIn = useCallback(async (email: string, password: string) => {
    await signIn(email, password);
    await detectUserCountry().catch(() => {});
    const p = await getProfile();
    setProfile(p);
    if (p && p.status !== 'active') {
      throw new Error('Your account is ' + p.status + '. Please contact support.');
    }
  }, []);

  const handleSignUp = useCallback(async (input: SignUpInput) => {
    await signUp(input);
  }, []);

  const handleSignOut = useCallback(async () => {
    await apiSignOut();
    setProfile(null);
    setImpersonation(null);
    sessionStorage.removeItem(STORAGE_KEY);
  }, []);

  const handleImpersonateUser = useCallback(async (
    targetUserId: string,
    targetUsername: string,
    accessToken: string,
    refreshToken: string,
  ) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) throw new Error('Not authenticated');

    const impState: ImpersonationState = {
      adminAccessToken: session.access_token,
      adminRefreshToken: session.refresh_token,
      adminUserId: session.user.id,
      impersonatedUserId: targetUserId,
      impersonatedUsername: targetUsername,
    };

    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(impState));
    setImpersonation(impState);

    const { error } = await supabase.auth.setSession({
      access_token: accessToken,
      refresh_token: refreshToken,
    });
    if (error) throw error;

    await refreshProfile();
  }, [refreshProfile]);

  const handleReturnToAdmin = useCallback(async () => {
    if (!impersonation) return;
    const { error } = await supabase.auth.setSession({
      access_token: impersonation.adminAccessToken,
      refresh_token: impersonation.adminRefreshToken,
    });
    if (error) throw error;

    sessionStorage.removeItem(STORAGE_KEY);
    setImpersonation(null);
    await refreshProfile();
  }, [impersonation, refreshProfile]);

  return (
    <AuthContext.Provider
      value={{
        profile,
        loading,
        signIn: handleSignIn,
        signUp: handleSignUp,
        signOut: handleSignOut,
        refreshProfile,
        impersonation,
        impersonateUser: handleImpersonateUser,
        returnToAdmin: handleReturnToAdmin,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
