import { createClient } from '@/lib/supabase/server';

export type ServerAuthSession = {
  userId: string | null;
  getToken: () => Promise<string | null>;
};

export async function getServerAuthSession(): Promise<ServerAuthSession> {
  const supabase = await createClient();
  const [{ data: userData }, { data: sessionData }] = await Promise.all([
    supabase.auth.getUser(),
    supabase.auth.getSession(),
  ]);

  return {
    userId: userData.user?.id ?? null,
    getToken: async () => sessionData.session?.access_token ?? null,
  };
}
