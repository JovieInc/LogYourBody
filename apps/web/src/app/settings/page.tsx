'use client';

import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  Loader2,
  User,
  Shield,
  Bell,
  Globe,
  ChevronRight,
  ArrowLeft,
  Heart,
  LogOut,
  Download,
} from 'lucide-react';
import Link from 'next/link';
import { MobileNavbar } from '@/components/MobileNavbar';
import { VersionDisplay } from '@/components/VersionDisplay';

export default function SettingsPage() {
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
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" aria-label="Loading" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  const primaryEmail =
    user.primaryEmailAddress?.emailAddress ?? user.emailAddresses?.[0]?.emailAddress ?? '';

  const memberSinceYear = user.createdAt?.getFullYear() ?? new Date().getFullYear();

  const settingsItems = [
    {
      title: 'Profile',
      description: 'Personal information and avatar',
      icon: User,
      href: '/settings/profile',
      badge: null,
    },
    {
      title: 'Account & Security',
      description: 'Phone and authentication',
      icon: Shield,
      href: '/settings/account',
      badge: null,
    },
    {
      title: 'Preferences',
      description: 'Units and measurement preferences',
      icon: Globe,
      href: '/settings/preferences',
      badge: null,
    },
    {
      title: 'Notifications',
      description: 'Reminders and email preferences',
      icon: Bell,
      href: '/settings/notifications',
      badge: null,
    },
    {
      title: 'Subscription',
      description: 'Manage your plan and billing',
      icon: Heart,
      href: '/settings/subscription',
      badge: 'Free',
    },
    {
      title: 'Export Data',
      description: 'Download all your data',
      icon: Download,
      href: '/settings/data-export',
      badge: null,
    },
  ];

  return (
    <div className="bg-linear-bg min-h-screen pb-16 md:pb-0">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/dashboard">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Settings</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto max-w-2xl px-4 py-6">
        <div className="mb-8 space-y-4">
          {/* User Info Card */}
          <Card className="bg-linear-card border-linear-border">
            <CardContent className="p-6">
              <div className="flex items-center gap-4">
                <div className="bg-linear-purple/10 flex h-16 w-16 items-center justify-center rounded-full">
                  <span className="text-linear-text text-xl font-bold">
                    {primaryEmail.charAt(0).toUpperCase()}
                  </span>
                </div>
                <div className="flex-1">
                  <h2 className="text-linear-text text-lg font-semibold">{primaryEmail}</h2>
                  <p className="text-linear-text-secondary text-sm">
                    Free Plan • Member since {memberSinceYear}
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Settings Menu Items */}
          <div className="space-y-2">
            {settingsItems.map((item) => (
              <Link key={item.href} href={item.href}>
                <Card className="bg-linear-card border-linear-border hover:bg-linear-card/80 cursor-pointer transition-colors">
                  <CardContent className="p-4">
                    <div className="flex items-center gap-4">
                      <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                        <item.icon className="text-linear-text h-5 w-5" />
                      </div>
                      <div className="flex-1">
                        <h3 className="text-linear-text font-medium">{item.title}</h3>
                        <p className="text-linear-text-secondary text-sm">{item.description}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        {item.badge && (
                          <Badge variant="secondary" className="text-xs">
                            {item.badge}
                          </Badge>
                        )}
                        <ChevronRight className="text-linear-text-tertiary h-4 w-4" />
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>

          {/* Sign Out Button */}
          <Card className="bg-linear-card border-linear-border mt-8">
            <CardContent className="p-4">
              <Button
                variant="ghost"
                className="w-full justify-start text-red-500 hover:bg-red-500/10 hover:text-red-400"
                onClick={signOut}
              >
                <LogOut className="mr-3 h-4 w-4" />
                Sign Out
              </Button>
            </CardContent>
          </Card>

          {/* App Version */}
          <div className="py-8 text-center">
            <div className="mb-2 flex items-center justify-center gap-2">
              <span className="text-linear-text-tertiary text-xs">LogYourBody</span>
              <VersionDisplay />
            </div>
            <div className="flex items-center justify-center gap-4">
              <Link
                href="/terms"
                className="text-linear-text-tertiary hover:text-linear-text text-xs"
              >
                Terms
              </Link>
              <span className="text-linear-text-tertiary">•</span>
              <Link
                href="/privacy"
                className="text-linear-text-tertiary hover:text-linear-text text-xs"
              >
                Privacy
              </Link>
              <span className="text-linear-text-tertiary">•</span>
              <Link
                href="/about"
                className="text-linear-text-tertiary hover:text-linear-text text-xs"
              >
                About
              </Link>
            </div>
          </div>
        </div>
      </main>

      {/* Mobile Navigation Bar */}
      <MobileNavbar />
    </div>
  );
}
