import { clerkMiddleware, createRouteMatcher } from '@clerk/nextjs/server';
import { NextFetchEvent, NextRequest, NextResponse } from 'next/server';

const isProtectedRoute = createRouteMatcher([
  '/dashboard(.*)',
  '/log(.*)',
  '/api/weights(.*)',
  '/api/auth/delete-account',
  '/api/parse-pdf',
  '/api/parse-pdf-alt',
  '/api/parse-pdf-v2',
  '/onboarding(.*)',
  '/settings(.*)',
  '/photos(.*)',
  '/steps(.*)',
  '/import(.*)',
]);

const _isPublicRoute = createRouteMatcher([
  '/signin(.*)',
  '/signup(.*)',
  '/login(.*)', // Keep for backwards compatibility
  '/',
  '/forgot-password(.*)',
  '/terms(.*)',
  '/privacy(.*)',
  '/about(.*)',
  '/blog(.*)',
  '/mobile(.*)',
]);

const productionDebugRoutePatterns = [
  /^\/debug(?:\/.*)?$/,
  /^\/debug-[^/]+(?:\/.*)?$/,
  /^\/test(?:\/.*)?$/,
  /^\/test-[^/]+(?:\/.*)?$/,
  /^\/api\/debug(?:\/.*)?$/,
  /^\/api\/debug-[^/]+(?:\/.*)?$/,
  /^\/api\/test-[^/]+(?:\/.*)?$/,
  /^\/basic-test(?:\/.*)?$/,
  /^\/compare-avatars(?:\/.*)?$/,
  /^\/diag(?:\/.*)?$/,
  /^\/login-test(?:\/.*)?$/,
  /^\/pwa-test(?:\/.*)?$/,
];

function normalizePathname(pathname: string) {
  if (pathname === '/') {
    return pathname;
  }

  return pathname.replace(/\/+$/, '');
}

export function isProductionDebugRoute(pathname: string) {
  const normalizedPathname = normalizePathname(pathname);
  return productionDebugRoutePatterns.some((pattern) => pattern.test(normalizedPathname));
}

export function shouldBlockDebugRoute(pathname: string) {
  return isProductionDebugRoute(pathname);
}

const protectedRouteMiddleware = clerkMiddleware(async (auth) => {
  await auth.protect();
});

export function shouldUseClerkMiddleware(req: NextRequest) {
  return isProtectedRoute(req);
}

export default function middleware(req: NextRequest, event: NextFetchEvent) {
  if (shouldBlockDebugRoute(req.nextUrl.pathname)) {
    return new NextResponse(null, {
      status: 404,
      headers: {
        'Cache-Control': 'no-store',
      },
    });
  }

  if (!shouldUseClerkMiddleware(req)) {
    return NextResponse.next();
  }

  return protectedRouteMiddleware(req, event);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - images - .svg, .png, .jpg, .jpeg, .gif, .webp
     * Feel free to modify this pattern to include more paths.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
