import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { publicEnv } from '@/env'

export async function updateSession(request: NextRequest) {
  try {
    let supabaseResponse = NextResponse.next({
      request,
    })

    const supabase = createServerClient(
      publicEnv.NEXT_PUBLIC_SUPABASE_URL,
      publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY,
      {
        cookies: {
          getAll() {
            return request.cookies.getAll()
          },
          setAll(cookiesToSet) {
            cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
            supabaseResponse = NextResponse.next({
              request,
            })
            cookiesToSet.forEach(({ name, value, options }) =>
              supabaseResponse.cookies.set(name, value, options)
            )
          },
        },
      }
    )

    // IMPORTANT: Avoid writing any logic between createServerClient and
    // supabase.auth.getUser(). A simple mistake could make your server
    // vulnerable to CSRF attacks.

    const {
      data: { user },
    } = await supabase.auth.getUser()

    const url = request.nextUrl.clone()
    const pathname = url.pathname
    
    // Define protected routes that require authentication
    const protectedRoutes = ['/dashboard', '/settings', '/profile', '/log', '/photos', '/steps']
    const isProtectedRoute = protectedRoutes.some(route => pathname.startsWith(route))
    
    // Allow auth callbacks to process
    if (pathname.startsWith('/auth/callback')) {
      return supabaseResponse
    }
    
    // Only redirect unauthenticated users away from protected routes
    // Don't redirect authenticated users from login pages (let client handle it)
    if (!user && isProtectedRoute) {
      url.pathname = '/signin'
      return NextResponse.redirect(url)
    }

    // IMPORTANT: You *must* return the supabaseResponse object as it is.
    // If you're trying to modify the response object based on the user's
    // authentication status, make sure to do it above.
    return supabaseResponse
  } catch (error) {
    // If there's an error with Supabase, allow the request to continue
    console.error('Middleware error:', error)
    return NextResponse.next({
      request,
    })
  }
}