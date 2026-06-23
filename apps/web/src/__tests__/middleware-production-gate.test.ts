/**
 * @jest-environment node
 */
import { readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { NextRequest } from 'next/server';

const mockProtect = jest.fn();
const mockProtectedMiddleware = jest.fn();

jest.mock('@clerk/nextjs/server', () => ({
  clerkMiddleware: jest.fn((handler) => {
    mockProtectedMiddleware.mockImplementation((request, event) =>
      handler({ protect: mockProtect }, request, event),
    );
    return mockProtectedMiddleware;
  }),
  createRouteMatcher: jest.fn((patterns: string[]) => {
    return (request: NextRequest) => {
      const pathname = request.nextUrl.pathname;

      return patterns.some((pattern) => {
        const prefix = pattern.replace('(.*)', '');
        return (
          pathname === prefix || pathname.startsWith(prefix.endsWith('/') ? prefix : `${prefix}/`)
        );
      });
    };
  }),
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

  afterEach(() => {
    if (originalVercelEnv === undefined) {
      delete process.env.VERCEL_ENV;
    } else {
      process.env.VERCEL_ENV = originalVercelEnv;
    }

    jest.resetModules();
    mockProtect.mockReset();
    mockProtectedMiddleware.mockReset();
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
    '/test-clerk-supabase',
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

    const response = await middleware(request, {} as never);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
    expect(mockProtectedMiddleware).not.toHaveBeenCalled();
    expect(mockProtect).not.toHaveBeenCalled();
  });

  it('blocks debug routes outside production deployments too', async () => {
    process.env.VERCEL_ENV = 'preview';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://preview.logyourbody.com/api/test-openai');

    expect(shouldBlockDebugRoute('/api/test-openai')).toBe(true);

    const response = await middleware(request, {} as never);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
    expect(mockProtectedMiddleware).not.toHaveBeenCalled();
    expect(mockProtect).not.toHaveBeenCalled();
  });

  it('keeps normal protected routes behind Clerk auth in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/dashboard');

    expect(shouldBlockDebugRoute('/dashboard')).toBe(false);

    const response = await middleware(request, {} as never);

    expect(response).toBeUndefined();
    expect(mockProtectedMiddleware).toHaveBeenCalledTimes(1);
    expect(mockProtect).toHaveBeenCalledTimes(1);
  });

  it('keeps normal public routes reachable in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
    const request = new NextRequest('https://logyourbody.com/about');

    expect(shouldBlockDebugRoute('/about')).toBe(false);

    const response = await middleware(request, {} as never);

    expect(response?.status).toBe(200);
    expect(mockProtectedMiddleware).not.toHaveBeenCalled();
    expect(mockProtect).not.toHaveBeenCalled();
  });

  it.each(['/', '/download/ios', '/privacy', '/support'])(
    'keeps marketing route %s outside Clerk protection in production',
    async (pathname) => {
      process.env.VERCEL_ENV = 'production';
      const { default: middleware, shouldBlockDebugRoute } = await import('../middleware');
      const request = new NextRequest(`https://logyourbody.com${pathname}`);

      expect(shouldBlockDebugRoute(pathname)).toBe(false);

      const response = await middleware(request, {} as never);

      expect(response?.status).toBe(200);
      expect(mockProtectedMiddleware).not.toHaveBeenCalled();
      expect(mockProtect).not.toHaveBeenCalled();
    },
  );
});
