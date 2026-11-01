/**
 * @jest-environment node
 */
import { readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { NextRequest } from 'next/server';

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
    '/test-identity-legacy',
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
  });

  it('blocks debug routes outside production deployments too', async () => {
    process.env.VERCEL_ENV = 'preview';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://preview.logyourbody.com/api/test-openai');

    expect(shouldBlockDebugRoute('/api/test-openai')).toBe(true);

    const response = await middleware(request);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
  });

  it('lets Next return a 404 for retired app pages even with a web session', async () => {
    process.env.VERCEL_ENV = 'production';
    const {
      default: middleware,
      shouldBlockDebugRoute,
      shouldUseProductAuthMiddleware,
    } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/settings', {
      headers: { cookie: 'lyb_access_token=test-token' },
    });

    expect(shouldBlockDebugRoute('/dashboard')).toBe(false);
    expect(shouldUseProductAuthMiddleware(request)).toBe(false);

    const response = await middleware(request);

    expect(response?.status).toBe(200);
  });

  it('sends a deleted product route home before sign-in', async () => {
    const { default: middleware } = await import('../middleware');
    const response = await middleware(
      new NextRequest('https://logyourbody.com/dashboard?tab=trend'),
    );

    expect(response?.status).toBe(307);
    expect(response?.headers.get('location')).toBe('https://logyourbody.com/');
  });

  it('leaves the retired settings root to Next without requiring sign-in', async () => {
    const { default: middleware } = await import('../middleware');
    const response = await middleware(
      new NextRequest('https://logyourbody.com/settings?tab=account'),
    );

    expect(response?.status).toBe(200);
    expect(response?.headers.get('location')).toBeNull();
  });

  it.each(['/settings/notifications', '/settings/preferences', '/settings/profile'])(
    'recovers the hidden %s route to the landing page',
    async (pathname) => {
      const { default: middleware } = await import('../middleware');
      const response = await middleware(new NextRequest(`https://logyourbody.com${pathname}`));
      expect(response.status).toBe(307);
      expect(response.headers.get('location')).toBe('https://logyourbody.com/');
    },
  );

  it.each(['/api/weights', '/api/auth/delete-account', '/api/parse-pdf', '/api/parse-pdf-v2'])(
    'preserves API authentication without redirecting %s to retired UI',
    async (pathname) => {
      const { default: middleware } = await import('../middleware');
      const url = `https://logyourbody.com${pathname}`;
      for (const authorization of ['', 'Basic invalid', 'Bearer', 'Bearer invalid token']) {
        const response = await middleware(new NextRequest(url, { headers: { authorization } }));
        expect(response.status).toBe(401);
        expect(response.headers.get('location')).toBeNull();
        expect(await response.json()).toEqual({ error: 'Unauthorized' });
      }
      // Presence only: the API handler still validates the bearer token.
      const native = await middleware(
        new NextRequest(url, {
          headers: { authorization: 'Bearer native-token' },
        }),
      );
      expect(native.status).toBe(200);
      expect(native.headers.get('location')).toBeNull();
    },
  );

  it.each(['/api/parse-pdf', '/api/parse-pdf-v2'])(
    'keeps advanced import API route %s behind product auth in production',
    async (pathname) => {
      process.env.VERCEL_ENV = 'production';
      const {
        default: middleware,
        shouldBlockDebugRoute,
        shouldUseProductAuthMiddleware,
      } = await import('../middleware');
      const request = new NextRequest(`https://logyourbody.com${pathname}`, {
        headers: { cookie: 'lyb_refresh_token=test-token' },
      });

      expect(shouldBlockDebugRoute(pathname)).toBe(false);
      expect(shouldUseProductAuthMiddleware(request)).toBe(true);

      const response = await middleware(request);

      expect(response?.status).toBe(200);
    },
  );

  it('does not broaden parse-PDF API protection to similarly named routes', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/api/parse-pdfish');

    expect(shouldBlockDebugRoute('/api/parse-pdfish')).toBe(false);

    const response = await middleware(request);

    expect(response?.status).toBe(200);
  });

  it('sends hidden marketing routes back to the launch entry', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/about');

    expect(shouldBlockDebugRoute('/about')).toBe(false);

    const response = await middleware(request);

    expect(response?.status).toBe(307);
    expect(response?.headers.get('location')).toBe('https://logyourbody.com/');
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
    },
  );

  it('does not assign an audience, rewrite the homepage or set a cookie (LYB-226)', async () => {
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = '1';
    const { default: middleware } = await import('../middleware');

    for (const url of [
      'https://logyourbody.com/',
      'https://logyourbody.com/?audience=women&goal=fat-loss',
    ]) {
      const response = await middleware(new NextRequest(url), {} as never);

      expect(response?.headers.get('x-middleware-rewrite')).toBeNull();
      expect(response?.headers.get('set-cookie')).toBeNull();
    }
  });
});
