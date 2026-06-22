import { auth, clerkClient } from '@clerk/nextjs/server';

export type ServerAuthSession = {
  userId: string | null;
  getToken: () => Promise<string | null>;
};

export async function getServerAuthSession(): Promise<ServerAuthSession> {
  const session = await auth();

  return {
    userId: session.userId,
    getToken: () => session.getToken(),
  };
}

export async function deleteServerAuthUser(userId: string) {
  const client = await clerkClient();
  await client.users.deleteUser(userId);
}
