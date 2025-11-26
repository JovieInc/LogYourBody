'use client';

import React, {
  createContext,
  useContext,
  useMemo,
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react';
import { useUser, useAuth as useClerkAuth, useSignIn, useSignUp, useClerk } from '@clerk/nextjs';
import { useRouter } from 'next/navigation';
import { processImageFile, validateImageFile } from '@/lib/clerk-avatar-upload';
import { analytics } from '@/lib/analytics';

type ClerkUserResource = ReturnType<typeof useUser>['user'];
type ClerkGetToken = ReturnType<typeof useClerkAuth>['getToken'];

type AuthExitReason = 'none' | 'userInitiated' | 'sessionExpired';

interface AuthSession {
  getToken: ClerkGetToken;
}

interface AuthContextType {
  user: ClerkUserResource | null;
  session: AuthSession | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
  signInWithProvider: (provider: 'google' | 'apple') => Promise<{ error: Error | null }>;
  uploadProfileImage: (file: File) => Promise<{ imageUrl?: string; error: Error | null }>;
  deleteProfileImage: () => Promise<{ error: Error | null }>;
  exitReason: AuthExitReason;
  clearExitReason: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function ClerkAuthProvider({ children }: { children: React.ReactNode }) {
  const { user, isLoaded } = useUser();
  const { signOut: clerkSignOut, getToken } = useClerkAuth();
  const { setActive } = useClerk();
  const { signIn: clerkSignIn } = useSignIn();
  const { signUp: clerkSignUp } = useSignUp();
  const router = useRouter();

  const [exitReason, setExitReason] = useState<AuthExitReason>('none');
  const previousUserIdRef = useRef<string | null>(null);

  // Load any stored exit reason on mount (e.g. after a redirect to /signin)
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const stored = window.sessionStorage.getItem('authExitReason');
    if (stored === 'sessionExpired' || stored === 'userInitiated') {
      setExitReason(stored as AuthExitReason);
    }
  }, []);

  // Persist exit reason for cross-navigation visibility
  useEffect(() => {
    if (typeof window === 'undefined') return;

    if (exitReason === 'none') {
      window.sessionStorage.removeItem('authExitReason');
    } else {
      window.sessionStorage.setItem('authExitReason', exitReason);
    }
  }, [exitReason]);

  // Detect session transitions from Clerk user changes
  useEffect(() => {
    if (!isLoaded) return;

    const currentUserId = user?.id ?? null;
    const previousUserId = previousUserIdRef.current;

    if (!previousUserId && currentUserId) {
      // New sign-in in this tab: clear any previous exit reason
      if (exitReason !== 'none') {
        setExitReason('none');
      }
    } else if (previousUserId && !currentUserId && exitReason === 'none') {
      // Session was lost without an explicit reason (e.g. expiry or remote sign-out)
      setExitReason('sessionExpired');
    }

    previousUserIdRef.current = currentUserId;
  }, [user?.id, isLoaded, exitReason]);

  const clearExitReason = useCallback(() => {
    setExitReason('none');
  }, []);

  // Sync Statsig user context with Clerk user state
  useEffect(() => {
    if (!isLoaded) return;

    if (user) {
      const email = user.primaryEmailAddress?.emailAddress ?? undefined;
      const nameParts = [user.firstName, user.lastName].filter(Boolean) as string[];
      const name = nameParts.length > 0 ? nameParts.join(' ') : undefined;

      analytics.identify(user.id, {
        email,
        name,
        platform: 'web',
      });
    } else {
      analytics.reset();
    }
  }, [user, isLoaded]);

  const signIn = useCallback(
    async (email: string, password: string) => {
      try {
        if (!clerkSignIn) throw new Error('Sign in not available');

        const result = await clerkSignIn.create({
          identifier: email,
          password,
        });

        if (result.status === 'complete') {
          await setActive({ session: result.createdSessionId });
          router.push('/dashboard');
          return { error: null };
        }

        return { error: new Error('Sign in failed') };
      } catch (error) {
        return { error: error as Error };
      }
    },
    [clerkSignIn, setActive, router],
  );

  const signUp = useCallback(
    async (email: string, password: string) => {
      try {
        if (!clerkSignUp) throw new Error('Sign up not available');

        const result = await clerkSignUp.create({
          emailAddress: email,
          password,
        });

        if (result.status === 'complete') {
          await setActive({ session: result.createdSessionId });
          return { error: null };
        }

        // Handle email verification if needed
        if (result.status === 'missing_requirements') {
          await result.prepareEmailAddressVerification({ strategy: 'email_code' });
          // You might want to redirect to email verification page here
        }

        return { error: null };
      } catch (error) {
        return { error: error as Error };
      }
    },
    [clerkSignUp, setActive],
  );

  const signOut = useCallback(async () => {
    setExitReason('userInitiated');
    await clerkSignOut();
    router.push('/');
  }, [clerkSignOut, router]);

  const signInWithProvider = useCallback(
    async (provider: 'google' | 'apple') => {
      try {
        if (!clerkSignIn) throw new Error('Sign in not available');

        const providerMap: Record<'google' | 'apple', 'oauth_google' | 'oauth_apple'> = {
          google: 'oauth_google',
          apple: 'oauth_apple',
        };

        await clerkSignIn.authenticateWithRedirect({
          strategy: providerMap[provider],
          redirectUrl: '/auth/callback',
          redirectUrlComplete: '/dashboard',
        });

        return { error: null };
      } catch (error) {
        return { error: error as Error };
      }
    },
    [clerkSignIn],
  );

  const uploadProfileImage = useCallback(
    async (file: File) => {
      try {
        if (!user) {
          throw new Error('User not authenticated');
        }

        // Validate the file
        const validation = validateImageFile(file);
        if (!validation.valid) {
          throw new Error(validation.error);
        }

        // Process the image (resize and compress to match iOS implementation)
        const processedBlob = await processImageFile(file);

        // Convert blob to File for Clerk API
        const processedFile = new File([processedBlob], file.name, {
          type: 'image/jpeg',
        });

        // Upload to Clerk using the user's setProfileImage method
        await user.setProfileImage({ file: processedFile });

        // Reload user to get updated imageUrl
        await user.reload();

        return { imageUrl: user.imageUrl, error: null };
      } catch (error) {
        console.error('Avatar upload error:', error);
        return { error: error as Error };
      }
    },
    [user],
  );

  const deleteProfileImage = useCallback(async () => {
    try {
      if (!user) {
        throw new Error('User not authenticated');
      }

      // Delete profile image using Clerk API
      await user.setProfileImage({ file: null });

      // Reload user to get updated state
      await user.reload();

      return { error: null };
    } catch (error) {
      console.error('Avatar delete error:', error);
      return { error: error as Error };
    }
  }, [user]);

  const value = useMemo(() => {
    const currentSession: AuthSession | null = isLoaded ? { getToken } : null;
    return {
      user,
      session: currentSession,
      loading: !isLoaded,
      signIn,
      signUp,
      signOut,
      signInWithProvider,
      uploadProfileImage,
      deleteProfileImage,
      exitReason,
      clearExitReason,
    };
  }, [
    user,
    getToken,
    isLoaded,
    signIn,
    signUp,
    signOut,
    signInWithProvider,
    uploadProfileImage,
    deleteProfileImage,
    exitReason,
    clearExitReason,
  ]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within a ClerkAuthProvider');
  }
  return context;
}

// Export alias for compatibility
export const AuthProvider = ClerkAuthProvider;
