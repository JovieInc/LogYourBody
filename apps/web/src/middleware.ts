import { NextRequest, NextResponse } from 'next/server';
import { isLandingAudience, type LandingAudience } from '@/lib/marketing/landing-registry';
import { updateSession } from '@/lib/supabase/middleware';

const LANDING_AUDIENCE_COOKIE = 'lyb_landing_audience_v1';
const protectedRoutePrefixes = [
  '/dashboard',
  '/log',
  '/api/weights',
  '/api/auth/delete-account',
  '/api/parse-pdf',
  '/api/parse-pdf-alt',
  '/api/parse-pdf-v2',
  '/onboarding',
  '/settings',
  '/photos',
  '/steps',
  '/import',
];

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
  return pathname === '/' ? pathname : pathname.replace(/\/+$/, '');
}

export function isProductionDebugRoute(pathname: string) {
  const normalizedPathname = normalizePathname(pathname);
  return productionDebugRoutePatterns.some((pattern) => pattern.test(normalizedPathname));
}

export function shouldBlockDebugRoute(pathname: string) {
  return isProductionDebugRoute(pathname);
}

export function shouldUseProductAuthMiddleware(req: NextRequest) {
  const pathname = normalizePathname(req.nextUrl.pathname);
  return protectedRoutePrefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

function randomLandingAudience(): LandingAudience {
  return Math.random() < 0.5 ? 'men' : 'women';
}

export function resolveLandingAudience(req: NextRequest) {
  const requested = req.nextUrl.searchParams.get('audience');
  if (isLandingAudience(requested)) return { audience: requested, source: 'campaign' as const };

  const stored = req.cookies.get(LANDING_AUDIENCE_COOKIE)?.value;
  if (isLandingAudience(stored)) return { audience: stored, source: 'returning' as const };

  return { audience: randomLandingAudience(), source: 'experiment' as const };
}

export default function middleware(req: NextRequest) {
  if (shouldBlockDebugRoute(req.nextUrl.pathname)) {
    return new NextResponse(null, { status: 404, headers: { 'Cache-Control': 'no-store' } });
  }

  if (
    req.nextUrl.pathname === '/' &&
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 === '1' &&
    !req.nextUrl.searchParams.has('_lyb_audience')
  ) {
    const assignment = resolveLandingAudience(req);
    const rewrittenUrl = req.nextUrl.clone();
    rewrittenUrl.searchParams.set('_lyb_audience', assignment.audience);
    rewrittenUrl.searchParams.set('_lyb_assignment_source', assignment.source);
    const response = NextResponse.rewrite(rewrittenUrl);
    response.cookies.set(LANDING_AUDIENCE_COOKIE, assignment.audience, {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      maxAge: 60 * 60 * 24 * 30,
      path: '/',
    });
    return response;
  }

  return updateSession(req);
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
