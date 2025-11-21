'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Separator } from '@/components/ui/separator'
import { toast } from '@/hooks/use-toast'
import {
  Loader2,
  ArrowLeft,
  Lock,
  Smartphone,
  Shield,
  AlertCircle,
  Check
} from 'lucide-react'
import Link from 'next/link'
import { format } from 'date-fns'

export default function AccountSettingsPage() {
  const { user, loading, signOut } = useAuth()
  const router = useRouter()
  const [isDeleting, setIsDeleting] = useState(false)

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

  if (!user) {
    return null
  }

  const primaryEmail = user.primaryEmailAddress?.emailAddress
    ?? user.emailAddresses?.[0]?.emailAddress
    ?? ''

  const emailVerified = user.emailAddresses?.some((address) => address.verification?.status === 'verified') ?? false

  const createdAt = user.createdAt
  const lastSignInAt = user.lastSignInAt

  const handlePasswordChange = () => {
    toast({
      title: "Password reset email sent",
      description: "Check your email for instructions to reset your password."
    })
  }

  const handleEnable2FA = () => {
    toast({
      title: "Coming soon",
      description: "Two-factor authentication will be available in a future update."
    })
  }

  const handleDeleteAccount = async () => {
    if (!window.confirm('Are you sure you want to delete your account? This action cannot be undone.')) {
      return
    }

    setIsDeleting(true)
    try {
      // TODO: Add actual API call to delete account
      // const { error } = await supabase.rpc('delete_user_account')

      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 2000))

      toast({
        title: "Account deleted",
        description: "Your account has been permanently deleted."
      })

      // Sign out the user after account deletion
      await signOut()

      // Redirect to home page
      router.push('/')
    } catch {
      toast({
        title: "Error",
        description: "Failed to delete account. Please try again.",
        variant: "destructive"
      })
    } finally {
      setIsDeleting(false)
    }
  }

  return (
    <div className="min-h-screen bg-linear-bg">
      {/* Header */}
      <header className="bg-linear-card shadow-sm border-b border-linear-border sticky top-0 z-10">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/settings">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-xl font-bold text-linear-text">Account & Security</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-2xl space-y-6">
        {/* Account Info */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Account Information</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-sm text-linear-text-secondary">Email</p>
                <p className="font-medium text-linear-text">{primaryEmail}</p>
              </div>
              <Badge
                variant={emailVerified ? "secondary" : "destructive"}
                className="text-xs"
              >
                {emailVerified ? (
                  <>
                    <Check className="h-3 w-3 mr-1" />
                    Verified
                  </>
                ) : (
                  'Unverified'
                )}
              </Badge>
            </div>

            <Separator className="bg-linear-border" />

            <div className="space-y-3">
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-linear-text-secondary">User ID</span>
                <span className="text-xs font-mono text-linear-text-tertiary">
                  {user.id?.slice(0, 8)}...
                </span>
              </div>
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-linear-text-secondary">Account Created</span>
                <span className="text-sm text-linear-text">
                  {createdAt ? format(createdAt, 'MMM d, yyyy') : 'Unknown'}
                </span>
              </div>
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-linear-text-secondary">Last Sign In</span>
                <span className="text-sm text-linear-text">
                  {lastSignInAt ? format(lastSignInAt, 'MMM d, yyyy') : 'Unknown'}
                </span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Security */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Security</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Manage your account security settings
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button
              variant="outline"
              className="w-full justify-start border-linear-border"
              onClick={handlePasswordChange}
            >
              <Lock className="h-4 w-4 mr-3" />
              Change Password
            </Button>

            <Button
              variant="outline"
              className="w-full justify-start border-linear-border"
              onClick={handleEnable2FA}
            >
              <Smartphone className="h-4 w-4 mr-3" />
              Enable Two-Factor Authentication
              <Badge variant="secondary" className="ml-auto text-xs">
                Coming Soon
              </Badge>
            </Button>

            <Button
              variant="outline"
              className="w-full justify-start border-linear-border"
              disabled
            >
              <Shield className="h-4 w-4 mr-3" />
              Security Log
              <span className="ml-auto text-xs text-linear-text-tertiary">
                View recent activity
              </span>
            </Button>
          </CardContent>
        </Card>

        {/* Danger Zone */}
        <Card className="bg-linear-card border-red-500/20">
          <CardHeader>
            <CardTitle className="text-red-500">Danger Zone</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Irreversible and destructive actions
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Alert className="border-red-500/20 bg-red-500/5">
              <AlertCircle className="h-4 w-4 text-red-500" />
              <AlertDescription className="text-linear-text-secondary">
                Once you delete your account, there is no going back. All your data will be permanently removed.
              </AlertDescription>
            </Alert>

            <Button
              variant="destructive"
              className="w-full"
              onClick={handleDeleteAccount}
              disabled={isDeleting}
            >
              {isDeleting ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Deleting Account...
                </>
              ) : (
                'Delete My Account'
              )}
            </Button>
          </CardContent>
        </Card>
      </main>
    </div>
  )
}