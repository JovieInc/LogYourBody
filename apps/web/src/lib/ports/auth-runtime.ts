'use client';

import { useAuth as useClerkAuth, useSignIn, useUser } from '@clerk/nextjs';

export type AuthProviderName = 'google' | 'apple';

export type AuthEmailAddress = {
  emailAddress: string;
  verification?: {
    status?: string | null;
  } | null;
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

type ClerkUserResource = ReturnType<typeof useUser>['user'];

function toEmailAddress(
  address: NonNullable<ClerkUserResource>['emailAddresses'][number],
): AuthEmailAddress {
  return {
    emailAddress: address.emailAddress,
    verification: address.verification
      ? {
          status: address.verification.status,
        }
      : null,
  };
}

function toAppAuthUser(user: ClerkUserResource): AppAuthUser | null {
  if (!user) return null;

  return {
    id: user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    fullName: user.fullName,
    imageUrl: user.imageUrl,
    createdAt: user.createdAt,
    lastSignInAt: user.lastSignInAt,
    primaryEmailAddress: user.primaryEmailAddress ? toEmailAddress(user.primaryEmailAddress) : null,
    emailAddresses: user.emailAddresses.map(toEmailAddress),
    setProfileImage: user.setProfileImage.bind(user),
    reload: user.reload.bind(user),
  };
}

export function useAuthRuntime() {
  const { user, isLoaded } = useUser();
  const { signOut, getToken } = useClerkAuth();
  const { signIn } = useSignIn();

  return {
    user: toAppAuthUser(user),
    isLoaded,
    getToken,
    signOut,
    signInWithProvider: async (provider: AuthProviderName) => {
      if (!signIn) throw new Error('Sign in not available');

      const providerMap: Record<AuthProviderName, 'oauth_google' | 'oauth_apple'> = {
        google: 'oauth_google',
        apple: 'oauth_apple',
      };

      await signIn.authenticateWithRedirect({
        strategy: providerMap[provider],
        redirectUrl: '/auth/callback',
        redirectUrlComplete: '/dashboard',
      });
    },
  };
}
