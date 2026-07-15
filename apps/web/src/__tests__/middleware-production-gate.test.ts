/**
 * @jest-environment node
 */
import { readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { NextRequest, NextResponse } from 'next/server';

const mockUpdateSession = jest.fn((request: NextRequest) => NextResponse.next({ request }));

jest.mock('@/lib/supabase/middleware', () => ({
  updateSession: (request: NextRequest) => mockUpdateSession(request),
}));

function collectAppRouteFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const fullPath = join(dir, entry);
    const stat = statSync(fullPath);

    if (stat.isDirectory()) {
      if (entry === '__tests__') {
        return [];
      }

      return collectAppRouteFiles(fullPath);
    }

    return /(?:^|\/)(?:page|route)\.(?:t|j)sx?$/.test(fullPath) ? [fullPath] : [];
  });
}

function toRoutePath(filePath: string) {
  const appDir = join(process.cwd(), 'src', 'app');
  const relativePath = filePath
    .slice(appDir.length + 1)
    .split(sep)
    .join('/');
  const routePath = relativePath
    .replace(/(?:^|\/)(?:page|route)\.(?:t|j)sx?$/, '')
    .replace(/(^|\/)\([^/]+\)/g, '$1')
    .replace(/\/+/g, '/')
    .replace(/\/$/, '');

  return routePath ? `/${routePath}` : '/';
}

function routeNameRequiresProductionDebugGate(pathname: string) {
  return [
    /^\/(?:api\/)?debug(?:\/.*)?$/,
    /^\/(?:api\/)?debug-[^/]+(?:\/.*)?$/,
    /^\/(?:api\/)?test(?:\/.*)?$/,
    /^\/(?:api\/)?test-[^/]+(?:\/.*)?$/,
    /^\/basic-test(?:\/.*)?$/,
    /^\/compare-avatars(?:\/.*)?$/,
    /^\/diag(?:\/.*)?$/,
    /^\/login-test(?:\/.*)?$/,
    /^\/pwa-test(?:\/.*)?$/,
  ].some((pattern) => pattern.test(pathname));
}

const discoveredProductionDebugRoutes = collectAppRouteFiles(join(process.cwd(), 'src', 'app'))
  .map(toRoutePath)
  .filter(routeNameRequiresProductionDebugGate)
  .sort();

describe('middleware production debug/test gate', () => {
  const originalVercelEnv = process.env.VERCEL_ENV;
  const originalLandingV2 = process.env.NEXT_PUBLIC_LYB_WAITLIST_V2;

  afterEach(() => {
    if (originalVercelEnv === undefined) {
      delete process.env.VERCEL_ENV;
    } else {
      process.env.VERCEL_ENV = originalVercelEnv;
    }

    if (originalLandingV2 === undefined) {
      delete process.env.NEXT_PUBLIC_LYB_WAITLIST_V2;
    } else {
      process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = originalLandingV2;
    }

    jest.resetModules();
    mockUpdateSession.mockReset();
    mockUpdateSession.mockImplementation((request: NextRequest) => NextResponse.next({ request }));
  });

  it('keeps debug/test routes out of the mounted production route inventory', () => {
    expect(discoveredProductionDebugRoutes).toEqual([]);
  });

  it.each([
    '/debug-auth',
    '/debug-login',
    '/debug',
    '/api/debug',
    '/api/debug/auth',
    '/api/debug-pdf',
    '/api/test-openai',
    '/test-identity-supabase',
    '/test',
    '/test-avatars',
    '/test-comprehensive',
    '/test-login',
    '/test-pdf',
    '/test-photo-upload',
    '/test-sms',
    '/test-storage',
    '/basic-test',
    '/compare-avatars',
    '/diag',
    '/login-test',
    '/pwa-test',
  ])('blocks %s in production before auth handling', async (pathname) => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest(`https://logyourbody.com${pathname}`);

    expect(shouldBlockDebugRoute(pathname)).toBe(true);

    const response = await middleware(request);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
    expect(mockUpdateSession).not.toHaveBeenCalled();
  });

  it('blocks debug routes outside production deployments too', async () => {
    process.env.VERCEL_ENV = 'preview';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://preview.logyourbody.com/api/test-openai');

    expect(shouldBlockDebugRoute('/api/test-openai')).toBe(true);

    const response = await middleware(request);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
    expect(mockUpdateSession).not.toHaveBeenCalled();
  });

  it('keeps normal protected routes behind product auth in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const {
      default: middleware,
      shouldBlockDebugRoute,
      shouldUseProductAuthMiddleware,
    } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/dashboard');

    expect(shouldBlockDebugRoute('/dashboard')).toBe(false);
    expect(shouldUseProductAuthMiddleware(request)).toBe(true);

    const response = await middleware(request);

    expect(response?.status).toBe(200);
    expect(mockUpdateSession).toHaveBeenCalledTimes(1);
  });

  it.each(['/api/parse-pdf', '/api/parse-pdf-alt', '/api/parse-pdf-v2'])(
    'keeps advanced import API route %s behind product auth in production',
    async (pathname) => {
      process.env.VERCEL_ENV = 'production';
      const {
        default: middleware,
        shouldBlockDebugRoute,
        shouldUseProductAuthMiddleware,
      } = await import('../middleware');
      const request = new NextRequest(`https://logyourbody.com${pathname}`);

      expect(shouldBlockDebugRoute(pathname)).toBe(false);
      expect(shouldUseProductAuthMiddleware(request)).toBe(true);

      const response = await middleware(request);

      expect(response?.status).toBe(200);
      expect(mockUpdateSession).toHaveBeenCalledTimes(1);
    },
  );

  it('does not broaden parse-PDF API protection to similarly named routes', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/api/parse-pdfish');

    expect(shouldBlockDebugRoute('/api/parse-pdfish')).toBe(false);

    const response = await middleware(request);

    expect(response?.status).toBe(200);
    expect(mockUpdateSession).toHaveBeenCalledTimes(1);
  });

  it('keeps normal public routes reachable in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/about');

    expect(shouldBlockDebugRoute('/about')).toBe(false);

    const response = await middleware(request);

    expect(response?.status).toBe(200);
    expect(mockUpdateSession).toHaveBeenCalledTimes(1);
  });

  it.each(['/', '/download/ios', '/privacy', '/support'])(
    'keeps marketing route %s outside product auth in production',
    async (pathname) => {
      process.env.VERCEL_ENV = 'production';
      const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
      const request = new NextRequest(`https://logyourbody.com${pathname}`);

      expect(shouldBlockDebugRoute(pathname)).toBe(false);

      const response = await middleware(request);

      expect(response?.status).toBe(200);
      expect(mockUpdateSession).toHaveBeenCalledTimes(1);
    },
  );

  it('assigns an explicit campaign audience through an internal rewrite and sticky cookie', async () => {
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = '1';
    const { default: middleware } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/?audience=women&goal=fat-loss');

    const response = await middleware(request);
    const rewrite = response?.headers.get('x-middleware-rewrite');

    expect(rewrite).toContain('_lyb_audience=women');
    expect(rewrite).toContain('_lyb_assignment_source=campaign');
    expect(response?.cookies.get('lyb_landing_audience_v1')?.value).toBe('women');
    expect(mockUpdateSession).not.toHaveBeenCalled();
  });

  it('reuses a returning audience assignment instead of randomizing again', async () => {
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = '1';
    const { default: middleware } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/', {
      headers: { cookie: 'lyb_landing_audience_v1=men' },
    });

    const response = await middleware(request);
    const rewrite = response?.headers.get('x-middleware-rewrite');

    expect(rewrite).toContain('_lyb_audience=men');
    expect(rewrite).toContain('_lyb_assignment_source=returning');
  });

  it('allocates an unassigned visitor to one of the two registered experiment arms', async () => {
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = '1';
    jest.spyOn(Math, 'random').mockReturnValueOnce(0.75);
    const { default: middleware } = await import('../middleware');
    const response = await middleware(new NextRequest('https://logyourbody.com/'), {} as never);
    const rewrite = response?.headers.get('x-middleware-rewrite');

    expect(rewrite).toContain('_lyb_audience=women');
    expect(rewrite).toContain('_lyb_assignment_source=experiment');
  });
});
