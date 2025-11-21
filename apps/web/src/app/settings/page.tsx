'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
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
  Download
} from 'lucide-react'
import Link from 'next/link'
import { MobileNavbar } from '@/components/MobileNavbar'
import { VersionDisplay } from '@/components/VersionDisplay'

export default function SettingsPage() {
  const { user, loading, signOut } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin')
    }
  }, [user, loading, router])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-linear-bg">
        <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" aria-label="Loading" />
      </div>
    )
  }

  if (!user) {
    return null
  }

  const primaryEmail = user.primaryEmailAddress?.emailAddress
    ?? user.emailAddresses?.[0]?.emailAddress
    ?? ''

  const memberSinceYear = user.createdAt?.getFullYear() ?? new Date().getFullYear()

  const settingsItems = [
    {
      title: 'Profile',
      description: 'Personal information and avatar',
      icon: User,
      href: '/settings/profile',
      badge: null
    },
    {
      title: 'Account & Security',
      description: 'Password and authentication',
      icon: Shield,
      href: '/settings/account',
      badge: null
    },
    {
      title: 'Preferences',
      description: 'Units and measurement preferences',
      icon: Globe,
      href: '/settings/preferences',
      badge: null
    },
    {
      title: 'Notifications',
      description: 'Reminders and email preferences',
      icon: Bell,
      href: '/settings/notifications',
      badge: null
    },
    {
      title: 'Subscription',
      description: 'Manage your plan and billing',
      icon: Heart,
      href: '/settings/subscription',
      badge: 'Free'
    },
    {
      title: 'Export Data',
      description: 'Download all your data',
      icon: Download,
      href: '/settings/data-export',
      badge: null
    }
  ]

  return (
    <div className="min-h-screen bg-linear-bg pb-16 md:pb-0">
      {/* Header */}
      <header className="bg-linear-card shadow-sm border-b border-linear-border sticky top-0 z-10">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/dashboard">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-xl font-bold text-linear-text">Settings</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-2xl">
        <div className="space-y-4 mb-8">
          {/* User Info Card */}
          <Card className="bg-linear-card border-linear-border">
            <CardContent className="p-6">
              <div className="flex items-center gap-4">
                <div className="h-16 w-16 rounded-full bg-linear-purple/10 flex items-center justify-center">
                  <span className="text-xl font-bold text-linear-text">
                    {primaryEmail.charAt(0).toUpperCase()}
                  </span>
                </div>
                <div className="flex-1">
                  <h2 className="text-lg font-semibold text-linear-text">{primaryEmail}</h2>
                  <p className="text-sm text-linear-text-secondary">
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
                <Card className="bg-linear-card border-linear-border hover:bg-linear-card/80 transition-colors cursor-pointer">
                  <CardContent className="p-4">
                    <div className="flex items-center gap-4">
                      <div className="h-10 w-10 rounded-lg bg-linear-purple/10 flex items-center justify-center">
                        <item.icon className="h-5 w-5 text-linear-text" />
                      </div>
                      <div className="flex-1">
                        <h3 className="font-medium text-linear-text">{item.title}</h3>
                        <p className="text-sm text-linear-text-secondary">{item.description}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        {item.badge && (
                          <Badge variant="secondary" className="text-xs">
                            {item.badge}
                          </Badge>
                        )}
                        <ChevronRight className="h-4 w-4 text-linear-text-tertiary" />
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
                className="w-full justify-start text-red-500 hover:text-red-400 hover:bg-red-500/10"
                onClick={signOut}
              >
                <LogOut className="h-4 w-4 mr-3" />
                Sign Out
              </Button>
            </CardContent>
          </Card>

          {/* App Version */}
          <div className="text-center py-8">
            <div className="flex items-center justify-center gap-2 mb-2">
              <span className="text-xs text-linear-text-tertiary">LogYourBody</span>
              <VersionDisplay />
            </div>
            <div className="flex items-center justify-center gap-4">
              <Link href="/terms" className="text-xs text-linear-text-tertiary hover:text-linear-text">
                Terms
              </Link>
              <span className="text-linear-text-tertiary">•</span>
              <Link href="/privacy" className="text-xs text-linear-text-tertiary hover:text-linear-text">
                Privacy
              </Link>
              <span className="text-linear-text-tertiary">•</span>
              <Link href="/about" className="text-xs text-linear-text-tertiary hover:text-linear-text">
                About
              </Link>
            </div>
          </div>
        </div>
      </main>

      {/* Mobile Navigation Bar */}
      <MobileNavbar />
    </div>
  )
}