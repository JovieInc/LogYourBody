import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Sign in',
  alternates: { canonical: '/signin' },
};

export default function SignInLayout({ children }: { children: React.ReactNode }) {
  return children;
}
