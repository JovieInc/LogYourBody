'use client';

import { ClerkProvider, SignIn, SignUp } from '@clerk/nextjs';
import type { ReactNode } from 'react';

const authAppearance = {
  baseTheme: undefined,
  variables: {
    colorPrimary: '#8b5cf6',
    colorText: '#e1e1e3',
    colorTextSecondary: '#a1a1a8',
    colorBackground: '#18181b',
    colorInputBackground: '#18181b',
    colorInputText: '#e1e1e3',
    borderRadius: '0.5rem',
  },
  elements: {
    rootBox: 'mx-auto',
    card: 'bg-linear-card border-linear-border shadow-xl',
    headerTitle: 'hidden',
    headerSubtitle: 'hidden',
    socialButtonsBlockButton: 'border-linear-border hover:bg-linear-hover',
    formButtonPrimary: 'bg-linear-purple hover:bg-linear-purple/90',
    footerActionLink: 'text-linear-purple hover:text-linear-purple/80',
    identityPreviewEditButton: 'text-linear-purple hover:text-linear-purple/80',
    formFieldLabel: 'text-linear-text-secondary',
    formFieldInput: 'bg-linear-bg border-linear-border text-linear-text',
    dividerLine: 'bg-linear-border',
    dividerText: 'text-linear-text-tertiary',
    link: 'text-linear-purple hover:text-linear-purple/80',
    formFieldAction: 'text-linear-purple hover:text-linear-purple/80',
    footerAction: 'text-linear-text-secondary',
  },
} as const;

export function AuthRuntimeProvider({ children }: { children: ReactNode }) {
  return <ClerkProvider>{children}</ClerkProvider>;
}

export function AuthSignUp() {
  return (
    <SignUp
      appearance={authAppearance}
      routing="path"
      path="/signup"
      signInUrl="/signin"
      afterSignUpUrl="/onboarding"
      afterSignInUrl="/dashboard"
      forceRedirectUrl="/onboarding"
    />
  );
}

export function AuthSignIn() {
  return (
    <SignIn
      appearance={authAppearance}
      routing="path"
      path="/signin"
      signUpUrl="/signup"
      afterSignInUrl="/dashboard"
      forceRedirectUrl="/dashboard"
    />
  );
}
