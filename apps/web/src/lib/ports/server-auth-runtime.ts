import { cookies } from 'next/headers';
import { authCookies, fetchUserInfo } from '@/lib/auth/jovie-oauth';

export type ServerAuthSession = {
  userId: string | null;
  getToken: () => Promise<string | null>;
};

export async function getServerAuthSession(): Promise<ServerAuthSession> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(authCookies.accessToken)?.value ?? null;
  const user = accessToken ? await fetchUserInfo(accessToken) : null;

  return {
    userId: user?.sub ?? null,
    getToken: async () => accessToken,
  };
}
