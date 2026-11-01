'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { cn } from '@/lib/utils';
import { Shield, Heart, Download, ArrowLeft } from 'lucide-react';

const settingsNav = [
  {
    title: 'Account',
    href: '/settings/account',
    icon: Shield,
  },
  {
    title: 'Subscription',
    href: '/settings/subscription',
    icon: Heart,
  },
  {
    title: 'Export Data',
    href: '/settings/data-export',
    icon: Download,
  },
];

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  // Mobile view - show settings page normally
  if (pathname === '/settings') {
    return <>{children}</>;
  }

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Desktop Layout with Sidebar */}
      <div className="hidden md:flex">
        {/* Sidebar */}
        <aside className="border-linear-border bg-linear-card sticky top-0 h-screen w-64 border-r">
          <div className="p-6">
            <Link href="/" className="mb-8 flex items-center gap-2">
              <ArrowLeft className="text-linear-text-secondary h-4 w-4" />
              <span className="text-linear-text-secondary text-sm">Back</span>
            </Link>

            <h2 className="text-linear-text mb-4 text-lg font-semibold">Settings</h2>

            <nav className="space-y-1">
              {settingsNav.map((item) => {
                const isActive = pathname === item.href;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={cn(
                      'flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors',
                      isActive
                        ? 'bg-linear-purple/10 text-linear-text'
                        : 'text-linear-text-secondary hover:text-linear-text hover:bg-linear-card',
                    )}
                  >
                    <item.icon className="h-4 w-4" />
                    {item.title}
                  </Link>
                );
              })}
            </nav>
          </div>
        </aside>

        {/* Main Content */}
        <main className="flex-1">{children}</main>
      </div>

      {/* Mobile Layout */}
      <div className="md:hidden">{children}</div>
    </div>
  );
}
