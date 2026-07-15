'use client';

import { useState, type ReactNode } from 'react';
import { createClient } from '@/lib/supabase/client';

export function AuthRuntimeProvider({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

function PhoneAuthButton() {
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function continueWithPhone() {
    setIsLoading(true);
    setErrorMessage(null);
    const supabase = createClient();
    const provider = 'custom:jovie' as Parameters<
      typeof supabase.auth.signInWithOAuth
    >[0]['provider'];
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    if (error) {
      setErrorMessage(error.message);
      setIsLoading(false);
    }
  }

  return (
    <div className="space-y-3">
      <button
        type="button"
        onClick={continueWithPhone}
        disabled={isLoading}
        className="bg-linear-purple hover:bg-linear-purple/90 w-full rounded-full px-5 py-3 font-medium text-white disabled:opacity-60"
      >
        {isLoading ? 'Connecting…' : 'Continue with phone'}
      </button>
      {errorMessage ? <p className="text-center text-sm text-red-400">{errorMessage}</p> : null}
    </div>
  );
}

export function AuthSignUp() {
  return <PhoneAuthButton />;
}

export function AuthSignIn() {
  return <PhoneAuthButton />;
}
