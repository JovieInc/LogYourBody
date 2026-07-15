'use client';

import type { ReactNode } from 'react';

export function AuthRuntimeProvider({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

function AppleAuthButton() {
  return (
    <a
      href="/api/auth/login"
      className="bg-linear-purple hover:bg-linear-purple/90 block w-full rounded-full px-5 py-3 text-center font-medium text-white"
    >
      Continue with Apple
    </a>
  );
}

export function AuthSignUp() {
  return <AppleAuthButton />;
}

export function AuthSignIn() {
  return <AppleAuthButton />;
}
