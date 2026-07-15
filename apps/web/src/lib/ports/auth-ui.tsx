'use client';

import type { ReactNode } from 'react';

export function AuthRuntimeProvider({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

function PhoneAuthButton() {
  return (
    <a
      href="/api/auth/login"
      className="bg-linear-purple hover:bg-linear-purple/90 block w-full rounded-full px-5 py-3 text-center font-medium text-white"
    >
      Continue with phone
    </a>
  );
}

export function AuthSignUp() {
  return <PhoneAuthButton />;
}

export function AuthSignIn() {
  return <PhoneAuthButton />;
}
