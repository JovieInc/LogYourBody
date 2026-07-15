'use client';

import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase/client';

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
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<AppAuthUser | null>(null);
  const [isLoaded, setIsLoaded] = useState(false);

  useEffect(() => {
    let active = true;

    const projectUser = async (): Promise<AppAuthUser | null> => {
      const { data } = await supabase.auth.getUser();
      if (!data.user) return null;
      const source = data.user;
      const metadata = source.user_metadata ?? {};
      const email = source.email
        ? { emailAddress: source.email, verification: { status: 'verified' } }
        : null;

      return {
        id: source.id,
        firstName: typeof metadata.first_name === 'string' ? metadata.first_name : null,
        lastName: typeof metadata.last_name === 'string' ? metadata.last_name : null,
        fullName:
          typeof metadata.full_name === 'string'
            ? metadata.full_name
            : typeof metadata.name === 'string'
              ? metadata.name
              : null,
        imageUrl: typeof metadata.avatar_url === 'string' ? metadata.avatar_url : '',
        createdAt: source.created_at ? new Date(source.created_at) : null,
        lastSignInAt: source.last_sign_in_at ? new Date(source.last_sign_in_at) : null,
        primaryEmailAddress: email,
        emailAddresses: email ? [email] : [],
        async setProfileImage({ file }) {
          if (!file) {
            const { error } = await supabase.auth.updateUser({ data: { avatar_url: null } });
            if (error) throw error;
            return;
          }

          const path = `${source.id}/profile.jpg`;
          const { error: uploadError } = await supabase.storage
            .from('avatars')
            .upload(path, file, { contentType: 'image/jpeg', upsert: true });
          if (uploadError) throw uploadError;
          const { data: publicURL } = supabase.storage.from('avatars').getPublicUrl(path);
          const { error: updateError } = await supabase.auth.updateUser({
            data: { avatar_url: publicURL.publicUrl },
          });
          if (updateError) throw updateError;
        },
        async reload() {
          await supabase.auth.getUser();
        },
      };
    };

    void projectUser().then((nextUser) => {
      if (active) {
        setUser(nextUser);
        setIsLoaded(true);
      }
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(() => {
      void projectUser().then((nextUser) => {
        if (active) {
          setUser(nextUser);
          setIsLoaded(true);
        }
      });
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, [supabase]);

  return {
    user,
    isLoaded,
    getToken: async () => {
      const { data } = await supabase.auth.getSession();
      return data.session?.access_token ?? null;
    },
    signOut: async () => {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
    },
    signInWithProvider: async (_provider: AuthProviderName) => {
      const provider = 'custom:jovie' as Parameters<
        typeof supabase.auth.signInWithOAuth
      >[0]['provider'];
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo: `${window.location.origin}/auth/callback` },
      });
      if (error) throw error;
    },
  };
}
