'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { getProfile } from '@/lib/supabase/profile';
import { useAuth } from '@/contexts/ClerkAuthContext';

export default function AuthCallbackPage() {
  const router = useRouter();
  const { loading, user } = useAuth();

  useEffect(() => {
    const checkOnboardingStatus = async () => {
      if (loading) return;

      if (user) {
        try {
          const profile = await getProfile(user.id);

          // Check if onboarding is completed
          if (profile?.onboarding_completed) {
            router.push('/dashboard');
          } else {
            router.push('/onboarding');
          }
        } catch {
          // If profile doesn't exist, redirect to onboarding
          router.push('/onboarding');
        }
      } else {
        router.push('/signin');
      }
    };

    checkOnboardingStatus();
  }, [router, loading, user]);

  return (
    <div className="bg-linear-bg flex min-h-screen items-center justify-center">
      <div className="text-center">
        <Loader2 className="text-linear-text-secondary mx-auto mb-4 h-8 w-8 animate-spin" />
        <p className="text-linear-text-secondary">Completing sign in...</p>
      </div>
    </div>
  );
}
