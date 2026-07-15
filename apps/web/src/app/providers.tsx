'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider } from 'next-themes';
import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { ProductAuthProvider } from '@/contexts/ProductAuthContext';
import { PWAProvider } from '@/components/PWAProvider';
import { AuthRuntimeProvider } from '@/lib/ports/auth-ui';

const authFreeMarketingPrefixes = [
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

export function needsProductAuthRuntime(pathname: string | null | undefined) {
  if (!pathname) {
    return true;
  }

  return !authFreeMarketingPrefixes.some((prefix) => {
    if (prefix === '/') {
      return pathname === '/';
    }

    return pathname === prefix || pathname.startsWith(`${prefix}/`);
  });
}

export function Providers({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const shouldLoadProductAuth = needsProductAuthRuntime(pathname);
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
        {shouldLoadProductAuth ? (
          <AuthRuntimeProvider>
            <ProductAuthProvider>
              <PWAProvider>{children}</PWAProvider>
            </ProductAuthProvider>
          </AuthRuntimeProvider>
        ) : (
          <>{children}</>
        )}
      </ThemeProvider>
    </QueryClientProvider>
  );
}
