'use client';

import { useCallback, useEffect, useState } from 'react';
import type { JovieUserInfo } from '@/lib/auth/constants';

export type AuthProviderName = 'jovie';

export type AuthEmailAddress = {
  emailAddress: string;
  verification?: { status?: string | null } | null;
};

export type AppAuthUser = {
  id: string;
  firstName: string | null;
  lastName: string | null;
  fullName: string | null;
  imageUrl: string;
  createdAt: Date | null;
  lastSignInAt: Date | null;
  primaryEmailAddress: AuthEmailAddress | null;
  emailAddresses: AuthEmailAddress[];
  setProfileImage: (input: { file: File | Blob | null }) => Promise<unknown>;
  reload: () => Promise<unknown>;
};

export type AppAuthSession = {
  getToken: () => Promise<string | null>;
};

export function useAuthRuntime() {
  const [user, setUser] = useState<AppAuthUser | null>(null);
  const [isLoaded, setIsLoaded] = useState(false);

  const loadSession = useCallback(async (): Promise<AppAuthUser | null> => {
    const response = await fetch('/api/auth/session', { cache: 'no-store' });
    if (!response.ok && response.status !== 401) throw new Error('Unable to load auth session');
    const payload = (await response.json()) as { user: JovieUserInfo | null };
    const source = payload.user;
    if (!source) return null;
    const email = source.email
      ? {
          emailAddress: source.email,
          verification: { status: source.email_verified === false ? 'unverified' : 'verified' },
        }
      : null;
    const name = source.name || null;

    return {
      id: source.sub,
      firstName: source.given_name || (name ? name.split(' ')[0] || null : null),
      lastName:
        source.family_name || (name?.includes(' ') ? name.split(' ').slice(1).join(' ') : null),
      fullName: name,
      imageUrl: source.picture || '',
      createdAt: null,
      lastSignInAt: null,
      primaryEmailAddress: email,
      emailAddresses: email ? [email] : [],
      async setProfileImage() {
        throw new Error('Profile image storage is not available during the Neon cutover');
      },
      async reload() {
        await loadSession();
      },
    };
  }, []);

  useEffect(() => {
    let active = true;
    void loadSession()
      .then((nextUser) => {
        if (active) {
          setUser(nextUser);
          setIsLoaded(true);
        }
      })
      .catch(() => {
        if (active) {
          setUser(null);
          setIsLoaded(true);
        }
      });

    return () => {
      active = false;
    };
  }, [loadSession]);

  return {
    user,
    isLoaded,
    getToken: async () => null,
    signOut: async () => {
      const response = await fetch('/api/auth/logout', { method: 'POST' });
      if (!response.ok) throw new Error('Unable to sign out');
      setUser(null);
    },
    signInWithProvider: async (_provider: AuthProviderName) => {
      window.location.assign('/api/auth/login');
    },
  };
}
