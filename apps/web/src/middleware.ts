import { NextRequest, NextResponse } from 'next/server';
import { authCookies } from '@/lib/auth/constants';
import { prefersMarkdown, varyOnAccept } from '@/lib/marketing/accept-markdown';
import {
  homepageMarkdown,
  markdownResponse,
  publicMarkdownEnabled,
  PUBLIC_MARKDOWN_HEADER,
} from '@/lib/marketing/public-markdown';

const protectedRoutePrefixes = [
  '/dashboard',
  '/log',
  '/api/weights',
  '/api/auth/delete-account',
  '/api/parse-pdf',
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

export default async function middleware(req: NextRequest) {
  const requestHeaders = new Headers(req.headers);
  requestHeaders.delete(PUBLIC_MARKDOWN_HEADER);
  const isPublicDocument =
    ['GET', 'HEAD'].includes(req.method) &&
    !req.headers.has('rsc') &&
    !req.headers.has('next-router-prefetch') &&
    !shouldUseProductAuthMiddleware(req) &&
    !['/api', '/_next', '/.well-known', '/signin', '/signup', '/login'].some(
      (prefix) => req.nextUrl.pathname === prefix || req.nextUrl.pathname.startsWith(prefix + '/'),
    );
  const wantsMarkdown = isPublicDocument && prefersMarkdown(req.headers.get('Accept'));
  function publicHeaders(response: NextResponse): NextResponse {
    if (isPublicDocument) varyOnAccept(response.headers);
    // Do not cache a gate-off/failure HTML response under a Markdown Accept key.
    if (wantsMarkdown) response.headers.set('Cache-Control', 'private, no-store');
    return response;
  }
  if (shouldBlockDebugRoute(req.nextUrl.pathname)) {
    return new NextResponse(null, { status: 404, headers: { 'Cache-Control': 'no-store' } });
  }

  if (wantsMarkdown && (await publicMarkdownEnabled())) {
    if (req.nextUrl.pathname === '/') {
      return markdownResponse(homepageMarkdown(), 200, req.method);
    }
    requestHeaders.set(PUBLIC_MARKDOWN_HEADER, '1');
  }

  if (shouldUseProductAuthMiddleware(req)) {
    const hasSession =
      Boolean(req.cookies.get(authCookies.accessToken)?.value) ||
      Boolean(req.cookies.get(authCookies.refreshToken)?.value);
    if (!hasSession) {
      const signIn = new URL('/signin', req.url);
      signIn.searchParams.set('returnTo', `${req.nextUrl.pathname}${req.nextUrl.search}`);
      return NextResponse.redirect(signIn);
    }
  }

  return publicHeaders(NextResponse.next({ request: { headers: requestHeaders } }));
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
