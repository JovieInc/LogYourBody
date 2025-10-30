import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { cookies } from 'next/headers'
import { publicEnv } from '@/env'
import { serverEnv } from '@/env-server'

export async function GET() {
  try {
    const cookieStore = await cookies()
    const supabase = await createClient()
    
    // Get session information
    const { data: { session }, error: sessionError } = await supabase.auth.getSession()
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    
    // Get all cookies for debugging
    const allCookies = cookieStore.getAll()
    const supabaseCookies = allCookies.filter(cookie => 
      cookie.name.includes('supabase') || cookie.name.includes('auth-token')
    )
    
    // Check environment variables
    const envVars = {
      NEXT_PUBLIC_SUPABASE_URL: !!publicEnv.NEXT_PUBLIC_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: !!publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY,
      SUPABASE_SERVICE_ROLE_KEY: !!serverEnv.SUPABASE_SERVICE_ROLE_KEY,
    }
    
    // Get request headers
    const headers = {
      'user-agent': cookieStore.get('user-agent')?.value || 'Not found',
      'accept': cookieStore.get('accept')?.value || 'Not found',
    }
    
    return NextResponse.json({
      timestamp: new Date().toISOString(),
      session: {
        exists: !!session,
        user: session?.user?.email || 'No user',
        error: sessionError?.message || null,
      },
      user: {
        exists: !!user,
        email: user?.email || 'No user',
        error: userError?.message || null,
      },
      cookies: {
        count: allCookies.length,
        supabaseCount: supabaseCookies.length,
        supabaseCookies: supabaseCookies.map(c => ({
          name: c.name,
          hasValue: !!c.value,
        })),
      },
      environment: envVars,
      headers,
    }, {
      status: 200,
      headers: {
        'Cache-Control': 'no-store, no-cache, must-revalidate',
      },
    })
  } catch (error) {
    return NextResponse.json({
      error: 'Debug endpoint error',
      message: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined,
    }, { status: 500 })
  }
}