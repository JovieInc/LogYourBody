import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { publicEnv } from '@/env'

export async function GET() {
  // Clear all auth-related cookies
  const cookieStore = await cookies()
  
  // Clear Supabase auth cookies
  cookieStore.delete('sb-auth-token')
  cookieStore.delete('sb-refresh-token')
  
  // Redirect to login
  return NextResponse.redirect(new URL('/signin', publicEnv.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'))
}