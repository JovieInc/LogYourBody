'use client';

import { createClient } from '@/lib/supabase/client';

export type SupabaseAuthUser = {
  id: string;
  email?: string | null;
  [key: string]: unknown;
};

export type SupabaseAuthSession = {
  user: SupabaseAuthUser;
  [key: string]: unknown;
};

type AuthChangeSubscription = {
  unsubscribe: () => void;
};

export type SupabaseAuthRuntime = {
  getSession: () => Promise<SupabaseAuthSession | null>;
  onAuthStateChange: (
    handler: (session: SupabaseAuthSession | null) => void,
  ) => AuthChangeSubscription;
  signInWithPassword: (email: string, password: string) => Promise<void>;
  signUpWithPassword: (email: string, password: string, redirectTo: string) => Promise<void>;
  signOut: () => Promise<void>;
  signInWithOAuth: (provider: 'google' | 'apple', redirectTo: string) => Promise<void>;
};

export function createSupabaseAuthRuntime(): SupabaseAuthRuntime {
  const supabase = createClient();

  return {
    async getSession() {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      return session as SupabaseAuthSession | null;
    },
    onAuthStateChange(handler) {
      const {
        data: { subscription },
      } = supabase.auth.onAuthStateChange((_event, session) => {
        handler(session as SupabaseAuthSession | null);
      });

      return subscription;
    },
    async signInWithPassword(email, password) {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
    },
    async signUpWithPassword(email, password, redirectTo) {
      const { error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: redirectTo,
        },
      });
      if (error) throw error;
    },
    async signOut() {
      await supabase.auth.signOut();
    },
    async signInWithOAuth(provider, redirectTo) {
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo,
        },
      });
      if (error) throw error;
    },
  };
}
