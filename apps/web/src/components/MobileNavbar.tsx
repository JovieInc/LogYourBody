'use client';

import { usePathname, useRouter } from 'next/navigation';
import { Home, Settings } from 'lucide-react';
import { cn } from '@/lib/utils';

export function MobileNavbar() {
  const pathname = usePathname();
  const router = useRouter();

  // Don't show navbar on log page or settings pages
  if (pathname === '/log' || pathname.startsWith('/settings')) {
    return null;
  }

  const navItems = [
    {
      icon: Home,
      label: 'Home',
      href: '/',
    },
    {
      icon: Settings,
      label: 'Settings',
      href: '/settings',
    },
  ];

  return (
    <div className="bg-linear-bg border-linear-border fixed right-0 bottom-0 left-0 z-50 border-t md:hidden">
      <div className="flex h-14 items-center justify-around px-4">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;

          return (
            <button
              key={item.href}
              onClick={() => router.push(item.href)}
              className="relative flex h-full flex-1 items-center justify-center transition-all duration-200"
              aria-label={item.label}
            >
              <Icon
                className={cn(
                  'h-6 w-6 transition-colors',
                  isActive ? 'text-linear-purple' : 'text-linear-text-secondary',
                )}
              />
            </button>
          );
        })}
      </div>
    </div>
  );
}
