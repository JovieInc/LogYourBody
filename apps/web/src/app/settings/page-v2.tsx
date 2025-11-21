'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect } from 'react'
import Link from 'next/link'
import {
  Loader2,
  User,
  Shield,
  Globe,
  Bell,
  Heart,
  ChevronRight,
  ArrowLeft,
  LogOut
} from 'lucide-react'
import { Button } from '@/components/ui/button'

export default function SettingsPageV2() {
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
        <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" />
      </div>
    )
  }

  if (!user) return null

  const primaryEmail = user.primaryEmailAddress?.emailAddress
    ?? user.emailAddresses?.[0]?.emailAddress
    ?? ''

  const handleSignOut = async () => {
    await signOut()
    router.push('/')
  }

  const settingsItems = [
    {
      title: 'Profile',
      description: 'Name, photo, and personal info',
      icon: User,
      href: '/settings/profile'
    },
    {
      title: 'Account',
      description: 'Security and account management',
      icon: Shield,
      href: '/settings/account'
    },
    {
      title: 'Preferences',
      description: 'Units and display settings',
      icon: Globe,
      href: '/settings/preferences'
    },
    {
      title: 'Notifications',
      description: 'Email and push notifications',
      icon: Bell,
      href: '/settings/notifications'
    },
    {
      title: 'Subscription',
      description: 'Billing and plan details',
      icon: Heart,
      href: '/settings/subscription'
    }
  ]

  return (
    <div className="min-h-screen bg-linear-bg">
      {/* Simplified Header */}
      <header className="border-b border-linear-border">
        <div className="container max-w-3xl mx-auto px-4 py-4">
          <div className="flex items-center gap-4">
            <Link href="/dashboard">
              <Button variant="ghost" size="icon" className="text-linear-text-secondary">
                <ArrowLeft className="h-4 w-4" />
              </Button>
            </Link>
            <h1 className="text-xl font-semibold text-linear-text">Settings</h1>
          </div>
        </div>
      </header>

      {/* Content */}
      <main className="container max-w-3xl mx-auto px-4 py-8">
        {/* User Info - Minimal */}
        <div className="mb-8">
          <p className="text-sm text-linear-text-secondary">{primaryEmail}</p>
        </div>

        {/* Settings List - Clean and Simple */}
        <div className="space-y-px bg-linear-card rounded-lg overflow-hidden border border-linear-border">
          {settingsItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="flex items-center justify-between p-4 hover:bg-linear-card/80 transition-colors"
            >
              <div className="flex items-center gap-4">
                <item.icon className="h-5 w-5 text-linear-text-secondary" />
                <div>
                  <p className="font-medium text-linear-text">{item.title}</p>
                  <p className="text-sm text-linear-text-secondary">{item.description}</p>
                </div>
              </div>
              <ChevronRight className="h-4 w-4 text-linear-text-tertiary" />
            </Link>
          ))}
        </div>

        {/* Sign Out - Separated */}
        <div className="mt-8">
          <Button
            variant="ghost"
            onClick={handleSignOut}
            className="text-red-500 hover:text-red-400 hover:bg-red-500/10"
          >
            <LogOut className="h-4 w-4 mr-2" />
            Sign Out
          </Button>
        </div>

        {/* Footer Links - Minimal */}
        <div className="mt-16 pt-8 border-t border-linear-border">
          <div className="flex items-center gap-4 text-xs text-linear-text-tertiary">
            <Link href="/terms" className="hover:text-linear-text">Terms</Link>
            <Link href="/privacy" className="hover:text-linear-text">Privacy</Link>
            <Link href="/about" className="hover:text-linear-text">About</Link>
          </div>
        </div>
      </main>
    </div>
  )
}