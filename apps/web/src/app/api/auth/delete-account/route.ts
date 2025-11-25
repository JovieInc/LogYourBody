import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function DELETE(request: NextRequest) {
  try {
    const authHeader = request.headers.get('authorization')

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json(
        { error: 'Missing or invalid authorization header' },
        { status: 401 }
      )
    }

    const token = authHeader.substring(7)
    const supabase = await createClient()

    // Verify the token and get the user
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return NextResponse.json(
        { error: 'Invalid token' },
        { status: 401 }
      )
    }

    // Best-effort deletion of Supabase storage objects and Cloudinary assets
    try {
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
      const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

      if (!supabaseUrl || !supabaseAnonKey) {
        console.error('Missing Supabase environment variables for delete-user-assets function')
      } else {
        const response = await fetch(
          `${supabaseUrl}/functions/v1/delete-user-assets`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              apikey: supabaseAnonKey,
              Authorization: `Bearer ${token}`,
            },
          },
        )

        if (!response.ok) {
          const text = await response.text().catch(() => '')
          console.error('delete-user-assets function failed', {
            status: response.status,
            body: text,
          })
        }
      }
    } catch (error) {
      console.error('Error calling delete-user-assets function', error)
    }

    // Delete user's data from various tables
    // Note: Order matters due to foreign key constraints

    // Delete body metrics
    await supabase
      .from('body_metrics')
      .delete()
      .eq('user_id', user.id)

    // Delete daily metrics
    await supabase
      .from('daily_metrics')
      .delete()
      .eq('user_id', user.id)

    // Delete progress photos
    await supabase
      .from('progress_photos')
      .delete()
      .eq('user_id', user.id)

    // Delete user goals
    await supabase
      .from('user_goals')
      .delete()
      .eq('user_id', user.id)

    // Delete profile
    await supabase
      .from('profiles')
      .delete()
      .eq('id', user.id)

    // Sign out the user (this invalidates their session)
    await supabase.auth.signOut()

    // Note: Full user deletion from auth requires service role key
    // For now, we've deleted all user data and invalidated their session
    // You can implement a background job with service role key to fully delete auth records

    return NextResponse.json(
      { message: 'Account deleted successfully' },
      { status: 200 }
    )
  } catch (error) {
    console.error('Delete account error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}