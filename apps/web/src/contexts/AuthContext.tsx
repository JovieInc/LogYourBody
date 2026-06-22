'use client';

import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  createSupabaseAuthRuntime,
  SupabaseAuthSession,
  SupabaseAuthUser,
} from '@/lib/ports/supabase-auth-runtime';

interface AuthContextType {
  user: SupabaseAuthUser | null;
  session: SupabaseAuthSession | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
  signInWithProvider: (provider: 'google' | 'apple') => Promise<{ error: Error | null }>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<SupabaseAuthUser | null>(null);
  const [session, setSession] = useState<SupabaseAuthSession | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  const authRuntime = useMemo(() => createSupabaseAuthRuntime(), []);

  useEffect(() => {
    // Check active sessions and sets the user
    authRuntime
      .getSession()
      .then((session) => {
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);
      })
      .catch((error) => {
        console.error('Failed to get session:', error);
        setLoading(false);
      });

    // Listen for changes on auth state (sign in, sign out, etc.)
    const subscription = authRuntime.onAuthStateChange((session) => {
      setSession(session);
      setUser(session?.user ?? null);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, [authRuntime]);

  const signIn = async (email: string, password: string) => {
    try {
      await authRuntime.signInWithPassword(email, password);
      router.push('/dashboard');
      return { error: null };
    } catch (error) {
      return { error: error as Error };
    }
  };

  const signUp = async (email: string, password: string) => {
    try {
      await authRuntime.signUpWithPassword(
        email,
        password,
        `${window.location.origin}/auth/callback`,
      );
      return { error: null };
    } catch (error) {
      return { error: error as Error };
    }
  };

  const signOut = async () => {
    await authRuntime.signOut();
    router.push('/');
  };

  const signInWithProvider = async (provider: 'google' | 'apple') => {
    try {
      await authRuntime.signInWithOAuth(provider, `${window.location.origin}/auth/callback`);
      return { error: null };
    } catch (error) {
      return { error: error as Error };
    }
  };

  const value = {
    user,
    session,
    loading,
    signIn,
    signUp,
    signOut,
    signInWithProvider,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
