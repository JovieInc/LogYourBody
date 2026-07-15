'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider } from 'next-themes';
import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { ClerkAuthProvider } from '@/contexts/ClerkAuthContext';
import { PWAProvider } from '@/components/PWAProvider';
import { AuthRuntimeProvider } from '@/lib/ports/auth-ui';

const clerkFreeMarketingPrefixes = [
  '/',
  '/about',
  '/blog',
  '/brand',
  '/careers',
  '/changelog',
  '/delete-account',
  '/download',
  '/health-disclosure',
  '/mobile',
  '/privacy',
  '/security',
  '/support',
  '/terms',
];

export function needsClerkRuntime(pathname: string | null | undefined) {
  if (!pathname) {
    return true;
  }

  return !clerkFreeMarketingPrefixes.some((prefix) => {
    if (prefix === '/') {
      return pathname === '/';
    }

    return pathname === prefix || pathname.startsWith(`${prefix}/`);
  });
}

export function Providers({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const shouldLoadClerk = needsClerkRuntime(pathname);
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false}>
        {shouldLoadClerk ? (
          <AuthRuntimeProvider>
            <ClerkAuthProvider>
              <PWAProvider>{children}</PWAProvider>
            </ClerkAuthProvider>
          </AuthRuntimeProvider>
        ) : (
          <>{children}</>
        )}
      </ThemeProvider>
    </QueryClientProvider>
  );
}
