import { createBrowserClient } from '@supabase/ssr'
import { publicEnv } from '@/env'

export function createClient() {
  const supabaseUrl = publicEnv.NEXT_PUBLIC_SUPABASE_URL
  const supabaseAnonKey = publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('Missing Supabase environment variables')
    throw new Error('Missing Supabase environment variables')
  }

  return createBrowserClient(supabaseUrl, supabaseAnonKey)
}

// For backward compatibility, export a singleton instance
export const supabase = createClient()
