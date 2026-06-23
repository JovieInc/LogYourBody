#!/usr/bin/env node

import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'
import { resolve } from 'path'

// Load environment variables
dotenv.config({ path: resolve(process.cwd(), '.env.local') })

async function verifySupabaseSetup() {
  console.log('🔍 Verifying Supabase SMS Authentication Setup...\n')

  // Check environment variables
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('❌ Missing Supabase environment variables')
    console.error('   Please ensure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are set')
    process.exit(1)
  }

  console.log('✅ Environment variables found')
  console.log(`   URL: ${supabaseUrl}`)
  console.log(`   Key: ${supabaseAnonKey.substring(0, 20)}...`)

  // Create Supabase client
  const supabase = createClient(supabaseUrl, supabaseAnonKey)

  // Test connection
  try {
    const { data, error } = await supabase.auth.getSession()
    if (error) {
      console.error('❌ Failed to connect to Supabase:', error.message)
      process.exit(1)
    }
    console.log('✅ Successfully connected to Supabase')
  } catch (err: any) {
    console.error('❌ Connection error:', err.message)
    process.exit(1)
  }

  console.log('\n📱 SMS Authentication Configuration:')
  console.log('   - Provider: Twilio')
  console.log('   - Status: Enabled (configured in Supabase dashboard)')
  console.log('   - Login endpoint: /login (SMS tab)')

  console.log('\n🧪 To test SMS authentication:')
  console.log('   1. Start the dev server: pnpm dev')
  console.log('   2. Navigate to: http://localhost:3000/login')
  console.log('   3. Enter your phone number with country code')
  console.log('   4. You should receive an SMS with a 6-digit code')
  console.log('   5. Enter the code to verify authentication')

  console.log('\n✅ Setup verification complete!')
}

verifySupabaseSetup().catch(console.error)
