import { headers } from 'next/headers'
import { NextRequest, NextResponse } from 'next/server'
import { Webhook } from 'svix'
import { WebhookEvent } from '@clerk/nextjs/server'
import { createClient } from '@supabase/supabase-js'
import { publicEnv } from '@/env'
import { serverEnv } from '@/env-server'

// Initialize Supabase Admin client (lazy initialization to prevent build errors)
function getSupabaseAdmin() {
  const url = publicEnv.NEXT_PUBLIC_SUPABASE_URL
  const key = serverEnv.SUPABASE_SERVICE_ROLE_KEY
  
  if (!url || !key) {
    throw new Error('Missing Supabase environment variables')
  }
  
  return createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}

export async function POST(req: NextRequest) {
  // Get the headers
  const headerPayload = await headers()
  const svix_id = headerPayload.get("svix-id")
  const svix_timestamp = headerPayload.get("svix-timestamp")
  const svix_signature = headerPayload.get("svix-signature")

  // If there are no headers, error out
  if (!svix_id || !svix_timestamp || !svix_signature) {
    return new NextResponse('Error occured -- no svix headers', { status: 400 })
  }

  // Get the body
  const payload = await req.json()
  const body = JSON.stringify(payload)

  // Create a new Svix instance with your webhook secret
  const wh = new Webhook(serverEnv.CLERK_WEBHOOK_SECRET || '')

  let evt: WebhookEvent

  // Verify the payload with the headers
  try {
    evt = wh.verify(body, {
      "svix-id": svix_id,
      "svix-timestamp": svix_timestamp,
      "svix-signature": svix_signature,
    }) as WebhookEvent
  } catch (err) {
    console.error('Error verifying webhook:', err)
    return new NextResponse('Error occured', { status: 400 })
  }

  // Handle the webhook
  const eventType = evt.type

  if (eventType === 'user.created' || eventType === 'user.updated') {
    const { id, email_addresses, first_name, last_name, image_url } = evt.data

    // Get primary email
    const primaryEmail = email_addresses.find(email => email.id === evt.data.primary_email_address_id)
    const email = primaryEmail?.email_address

    // Create or update user profile in Supabase
    const profileData = {
      id,
      email,
      name: [first_name, last_name].filter(Boolean).join(' ') || null,
      avatar_url: image_url,
      email_verified: primaryEmail?.verification?.status === 'verified',
      updated_at: new Date().toISOString(),
    }

    try {
      const supabaseAdmin = getSupabaseAdmin()
      
      // Upsert profile
      const { error: profileError } = await supabaseAdmin
        .from('profiles')
        .upsert(profileData, {
          onConflict: 'id',
        })

      if (profileError) {
        console.error('Error upserting profile:', profileError)
        return new NextResponse('Error creating profile', { status: 500 })
      }

      // If this is a new user, also create email subscription preferences
      if (eventType === 'user.created') {
        const { error: subError } = await supabaseAdmin
          .from('email_subscriptions')
          .insert({
            user_id: id,
            weekly_summary: true,
            achievement_notifications: true,
            reminder_notifications: true,
            product_updates: false,
          })

        if (subError && subError.code !== '23505') { // Ignore duplicate key errors
          console.error('Error creating email subscription:', subError)
        }
      }

      console.log(`User ${eventType === 'user.created' ? 'created' : 'updated'}: ${id}`)
    } catch (error) {
      console.error('Error processing webhook:', error)
      return new NextResponse('Error processing webhook', { status: 500 })
    }
  }

  if (eventType === 'user.deleted') {
    const { id } = evt.data

    try {
      const supabaseAdmin = getSupabaseAdmin()
      
      // Delete user profile (cascade will handle related data)
      const { error } = await supabaseAdmin
        .from('profiles')
        .delete()
        .eq('id', id)

      if (error) {
        console.error('Error deleting profile:', error)
        return new NextResponse('Error deleting profile', { status: 500 })
      }

      console.log(`User deleted: ${id}`)
    } catch (error) {
      console.error('Error processing webhook:', error)
      return new NextResponse('Error processing webhook', { status: 500 })
    }
  }

  return new NextResponse('', { status: 200 })
}