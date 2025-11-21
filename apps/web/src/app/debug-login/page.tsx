'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Loader2 } from 'lucide-react'
import type { Session, User } from '@supabase/supabase-js'

type AuthContextValue = ReturnType<typeof useAuth>

interface DebugInfo {
  auth: {
    user: AuthContextValue['user']
    session: AuthContextValue['session']
    loading: boolean
    error: string | null
  }
  supabase: {
    session: Session | null
    user: User | null
    error: string | null
  }
  browser: {
    cookies: string
    localStorage: Record<string, string | null>
    sessionStorage: Record<string, string | null>
  }
  network: {
    online: boolean
    userAgent: string
  }
  console: {
    errors: string[]
    warnings: string[]
  }
}

export default function DebugLoginPage() {
  const [debugInfo, setDebugInfo] = useState<DebugInfo | null>(null)
  const [loading, setLoading] = useState(true)
  const [apiDebug, setApiDebug] = useState<Record<string, unknown> | null>(null)
  const { user, session, loading: authLoading } = useAuth()
  const supabase = useMemo(() => createClient(), [])
  
  // Capture console errors
  const [consoleErrors, setConsoleErrors] = useState<string[]>([])
  const [consoleWarnings, setConsoleWarnings] = useState<string[]>([])
  
  useEffect(() => {
    // Override console methods to capture errors
    const originalError = console.error
    const originalWarn = console.warn
    
    console.error = (...args: unknown[]) => {
      setConsoleErrors(prev => [...prev, args.join(' ')])
      originalError(...args)
    }
    
    console.warn = (...args: unknown[]) => {
      setConsoleWarnings(prev => [...prev, args.join(' ')])
      originalWarn(...args)
    }
    
    return () => {
      console.error = originalError
      console.warn = originalWarn
    }
  }, [])
  
  useEffect(() => {
    async function gatherDebugInfo() {
      try {
        // Get Supabase session directly
        const { data: { session: supabaseSession }, error: sessionError } = await supabase.auth.getSession()
        const { data: { user: supabaseUser }, error: userError } = await supabase.auth.getUser()
        
        // Get browser storage
        const localStorage: Record<string, string | null> = {}
        const sessionStorage: Record<string, string | null> = {}
        
        try {
          for (let i = 0; i < window.localStorage.length; i++) {
            const key = window.localStorage.key(i)
            if (key) {
              localStorage[key] = window.localStorage.getItem(key)
            }
          }
          
          for (let i = 0; i < window.sessionStorage.length; i++) {
            const key = window.sessionStorage.key(i)
            if (key) {
              sessionStorage[key] = window.sessionStorage.getItem(key)
            }
          }
        } catch (e) {
          console.error('Error accessing storage:', e)
        }
        
        setDebugInfo({
          auth: {
            user,
            session,
            loading: authLoading,
            error: null,
          },
          supabase: {
            session: supabaseSession,
            user: supabaseUser,
            error: sessionError?.message || userError?.message || null,
          },
          browser: {
            cookies: document.cookie,
            localStorage,
            sessionStorage,
          },
          network: {
            online: navigator.onLine,
            userAgent: navigator.userAgent,
          },
          console: {
            errors: consoleErrors,
            warnings: consoleWarnings,
          },
        })
      } catch (error: unknown) {
        console.error('Debug error:', error)
        setDebugInfo({
          auth: {
            user: null,
            session: null,
            loading: false,
            error: 'Failed to get auth info',
          },
          supabase: {
            session: null,
            user: null,
            error: error instanceof Error ? error.message : 'Unknown error',
          },
          browser: {
            cookies: '',
            localStorage: {},
            sessionStorage: {},
          },
          network: {
            online: false,
            userAgent: '',
          },
          console: {
            errors: consoleErrors,
            warnings: consoleWarnings,
          },
        })
      } finally {
        setLoading(false)
      }
    }
    
    gatherDebugInfo()
  }, [user, session, authLoading, supabase, consoleErrors, consoleWarnings])
  
  const fetchApiDebug = async () => {
    try {
      const response = await fetch('/api/debug/auth')
      const data = await response.json()
      setApiDebug(data)
    } catch (error: unknown) {
      setApiDebug({ error: error instanceof Error ? error.message : 'Failed to fetch' })
    }
  }
  
  const testLoginRoute = async () => {
    try {
      const response = await fetch('/login', {
        headers: {
          'Accept': 'text/html',
        },
      })
      alert(`Login route status: ${response.status}, redirected: ${response.redirected}, url: ${response.url}`)
    } catch (error: unknown) {
      alert(`Login route error: ${error instanceof Error ? error.message : 'Unknown error'}`)
    }
  }
  
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    )
  }
  
  return (
    <div className="container mx-auto p-4 space-y-4">
      <h1 className="text-2xl font-bold mb-4">Login Debug Information</h1>
      
      <div className="space-y-2">
        <Button onClick={fetchApiDebug} variant="outline">
          Fetch Server Debug Info
        </Button>
        <Button onClick={testLoginRoute} variant="outline" className="ml-2">
          Test Login Route
        </Button>
      </div>
      
      <Card>
        <CardHeader>
          <CardTitle>AuthContext State</CardTitle>
        </CardHeader>
        <CardContent>
          <pre className="text-xs overflow-auto">
            {JSON.stringify(debugInfo?.auth, null, 2)}
          </pre>
        </CardContent>
      </Card>
      
      <Card>
        <CardHeader>
          <CardTitle>Supabase Direct Check</CardTitle>
        </CardHeader>
        <CardContent>
          <pre className="text-xs overflow-auto">
            {JSON.stringify(debugInfo?.supabase, null, 2)}
          </pre>
        </CardContent>
      </Card>
      
      <Card>
        <CardHeader>
          <CardTitle>Browser Info</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            <div>
              <strong>Online:</strong> {debugInfo?.network.online ? 'Yes' : 'No'}
            </div>
            <div>
              <strong>Cookies:</strong>
              <pre className="text-xs overflow-auto mt-1">
                {debugInfo?.browser.cookies || 'No cookies'}
              </pre>
            </div>
            <div>
              <strong>LocalStorage (Supabase):</strong>
              <pre className="text-xs overflow-auto mt-1">
                {JSON.stringify(
                  Object.entries(debugInfo?.browser.localStorage || {})
                    .filter(([key]) => key.includes('supabase'))
                    .reduce((acc, [key, value]) => ({ ...acc, [key]: value }), {}),
                  null,
                  2
                )}
              </pre>
            </div>
          </div>
        </CardContent>
      </Card>
      
      <Card>
        <CardHeader>
          <CardTitle>Console Output</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            <div>
              <strong>Errors ({debugInfo?.console.errors.length || 0}):</strong>
              <pre className="text-xs overflow-auto mt-1 text-red-500">
                {debugInfo?.console.errors.join('\n') || 'No errors'}
              </pre>
            </div>
            <div>
              <strong>Warnings ({debugInfo?.console.warnings.length || 0}):</strong>
              <pre className="text-xs overflow-auto mt-1 text-yellow-500">
                {debugInfo?.console.warnings.join('\n') || 'No warnings'}
              </pre>
            </div>
          </div>
        </CardContent>
      </Card>
      
      {apiDebug && (
        <Card>
          <CardHeader>
            <CardTitle>Server Debug Info</CardTitle>
          </CardHeader>
          <CardContent>
            <pre className="text-xs overflow-auto">
              {JSON.stringify(apiDebug, null, 2)}
            </pre>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
