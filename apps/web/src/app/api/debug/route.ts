import { NextResponse } from 'next/server'
import { publicEnv } from '@/env'
import { serverEnv } from '@/env-server'

export async function GET() {
  // Only show debug info in non-production or with a secret
  const isDebugAllowed = publicEnv.NODE_ENV !== 'production' ||
                        serverEnv.DEBUG_SECRET === 'your-secret-here'
  
  if (!isDebugAllowed) {
    return NextResponse.json({ error: 'Debug not allowed' }, { status: 403 })
  }
  
  const debugInfo = {
    node_version: process.version,
    vercel_env: publicEnv.VERCEL_ENV,
    node_env: publicEnv.NODE_ENV,
    has_supabase_url: !!publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    has_anon_key: !!publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    has_database_url: !!serverEnv.DATABASE_URL,
    has_postgres_url: !!serverEnv.POSTGRES_URL,
    build_target: serverEnv.BUILD_TARGET,
    next_version: process.env.npm_package_dependencies_next || 'unknown',
  }
  
  return NextResponse.json(debugInfo)
}