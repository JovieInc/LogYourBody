'use client';

import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import Link from 'next/link';
import {
  Loader2,
  User,
  Shield,
  Globe,
  Bell,
  Heart,
  ChevronRight,
  ArrowLeft,
  LogOut,
} from 'lucide-react';
import { Button } from '@/components/ui/button';

export default function SettingsPageV2() {
  const { user, loading, signOut } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) return null;

  const primaryEmail =
    user.primaryEmailAddress?.emailAddress ?? user.emailAddresses?.[0]?.emailAddress ?? '';

  const handleSignOut = async () => {
    await signOut();
    router.push('/');
  };

  const settingsItems = [
    {
      title: 'Profile',
      description: 'Name, photo, and personal info',
      icon: User,
      href: '/settings/profile',
    },
    {
      title: 'Account',
      description: 'Security and account management',
      icon: Shield,
      href: '/settings/account',
    },
    {
      title: 'Preferences',
      description: 'Units and display settings',
      icon: Globe,
      href: '/settings/preferences',
    },
    {
      title: 'Notifications',
      description: 'Email and push notifications',
      icon: Bell,
      href: '/settings/notifications',
    },
    {
      title: 'Subscription',
      description: 'Billing and plan details',
      icon: Heart,
      href: '/settings/subscription',
    },
  ];

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Simplified Header */}
      <header className="border-linear-border border-b">
        <div className="container mx-auto max-w-3xl px-4 py-4">
          <div className="flex items-center gap-4">
            <Link href="/dashboard">
              <Button variant="ghost" size="icon" className="text-linear-text-secondary">
                <ArrowLeft className="h-4 w-4" />
              </Button>
            </Link>
            <h1 className="text-linear-text text-xl font-semibold">Settings</h1>
          </div>
        </div>
      </header>

      {/* Content */}
      <main className="container mx-auto max-w-3xl px-4 py-8">
        {/* User Info - Minimal */}
        <div className="mb-8">
          <p className="text-linear-text-secondary text-sm">{primaryEmail}</p>
        </div>

        {/* Settings List - Clean and Simple */}
        <div className="bg-linear-card border-linear-border space-y-px overflow-hidden rounded-lg border">
          {settingsItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="hover:bg-linear-card/80 flex items-center justify-between p-4 transition-colors"
            >
              <div className="flex items-center gap-4">
                <item.icon className="text-linear-text-secondary h-5 w-5" />
                <div>
                  <p className="text-linear-text font-medium">{item.title}</p>
                  <p className="text-linear-text-secondary text-sm">{item.description}</p>
                </div>
              </div>
              <ChevronRight className="text-linear-text-tertiary h-4 w-4" />
            </Link>
          ))}
        </div>

        {/* Sign Out - Separated */}
        <div className="mt-8">
          <Button
            variant="ghost"
            onClick={handleSignOut}
            className="text-red-500 hover:bg-red-500/10 hover:text-red-400"
          >
            <LogOut className="mr-2 h-4 w-4" />
            Sign Out
          </Button>
        </div>

        {/* Footer Links - Minimal */}
        <div className="border-linear-border mt-16 border-t pt-8">
          <div className="text-linear-text-tertiary flex items-center gap-4 text-xs">
            <Link href="/terms" className="hover:text-linear-text">
              Terms
            </Link>
            <Link href="/privacy" className="hover:text-linear-text">
              Privacy
            </Link>
            <Link href="/about" className="hover:text-linear-text">
              About
            </Link>
          </div>
        </div>
      </main>
    </div>
  );
}
