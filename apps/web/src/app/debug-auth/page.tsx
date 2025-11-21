'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useRouter } from 'next/navigation'
import type { User } from '@supabase/supabase-js'

export default function DebugAuthPage() {
  const { user, session, loading: authLoading } = useAuth()
  const [supabaseUser, setSupabaseUser] = useState<User | null>(null)
  const [isChecking, setIsChecking] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])

  const checkAuth = useCallback(async () => {
    try {
      setIsChecking(true)
      const { data: { user }, error } = await supabase.auth.getUser()
      if (error) {
        setError(error.message)
      } else {
        setSupabaseUser(user)
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to check auth')
    } finally {
      setIsChecking(false)
    }
  }, [supabase])

  useEffect(() => {
    checkAuth()
  }, [checkAuth])

  const signOut = async () => {
    await supabase.auth.signOut()
    router.push('/')
  }

  return (
    <div className="min-h-screen p-8 bg-linear-bg">
      <div className="max-w-4xl mx-auto space-y-6">
        <h1 className="text-3xl font-bold text-linear-text">Auth Debug Page</h1>
        
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Auth Context Status</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p><strong>Loading:</strong> {authLoading ? 'Yes' : 'No'}</p>
            <p><strong>User:</strong> {user ? user.email : 'None'}</p>
            <p><strong>Session:</strong> {session ? 'Active' : 'None'}</p>
            {user && (
              <pre className="bg-black/20 p-4 rounded overflow-auto text-xs">
                {JSON.stringify(user, null, 2)}
              </pre>
            )}
          </CardContent>
        </Card>

        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Direct Supabase Check</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p><strong>Checking:</strong> {isChecking ? 'Yes' : 'No'}</p>
            <p><strong>User:</strong> {supabaseUser ? supabaseUser.email : 'None'}</p>
            {error && <p className="text-red-500"><strong>Error:</strong> {error}</p>}
            {supabaseUser && (
              <pre className="bg-black/20 p-4 rounded overflow-auto text-xs">
                {JSON.stringify(supabaseUser, null, 2)}
              </pre>
            )}
          </CardContent>
        </Card>

        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Browser Info</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p><strong>Current Path:</strong> {typeof window !== 'undefined' ? window.location.pathname : 'SSR'}</p>
            <p><strong>User Agent:</strong> {typeof window !== 'undefined' ? navigator.userAgent : 'SSR'}</p>
            <p><strong>Cookies Enabled:</strong> {typeof window !== 'undefined' ? navigator.cookieEnabled ? 'Yes' : 'No' : 'SSR'}</p>
          </CardContent>
        </Card>

        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Actions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex gap-4">
              <Button onClick={checkAuth}>Refresh Auth Status</Button>
              <Button onClick={() => router.push('/signin')}>Go to Login</Button>
              <Button onClick={() => router.push('/dashboard')}>Go to Dashboard</Button>
              {(user || supabaseUser) && (
                <Button variant="destructive" onClick={signOut}>Sign Out</Button>
              )}
            </div>
          </CardContent>
        </Card>

        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Environment Check</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p><strong>NEXT_PUBLIC_SUPABASE_URL:</strong> {process.env.NEXT_PUBLIC_SUPABASE_URL ? 'Set' : 'Not Set'}</p>
            <p><strong>NEXT_PUBLIC_SUPABASE_ANON_KEY:</strong> {process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ? 'Set' : 'Not Set'}</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
