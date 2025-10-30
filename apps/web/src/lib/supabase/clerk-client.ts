import { createClient } from '@supabase/supabase-js'
import { useSession } from '@clerk/nextjs'
import { useMemo } from 'react'
import { publicEnv } from '@/env'

// Hook for client-side usage with Clerk (based on Clerk docs)
export function useClerkSupabaseClient() {
  const { session } = useSession()
  
  const supabaseUrl = publicEnv.NEXT_PUBLIC_SUPABASE_URL
  const supabaseAnonKey = publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('Missing Supabase environment variables')
  }

  return useMemo(() => {
    return createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {},
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      accessToken: async () => {
        if (!session) return null
        // Use the native integration instead of JWT template
        return await session.getToken() ?? null
      },
    })
  }, [session, supabaseUrl, supabaseAnonKey])
}

// For server-side usage with Clerk
export async function createClerkSupabaseClient(getToken: () => Promise<string | null>) {
  const supabaseUrl = publicEnv.NEXT_PUBLIC_SUPABASE_URL
  const supabaseAnonKey = publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('Missing Supabase environment variables')
  }
  
  return createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {},
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    accessToken: async () => {
      // Use the native integration
      return await getToken() ?? null
    },
  })
}