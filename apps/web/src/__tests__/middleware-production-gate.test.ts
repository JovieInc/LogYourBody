/**
 * @jest-environment node
 */
import { NextRequest } from 'next/server';

jest.mock('@clerk/nextjs/server', () => ({
  clerkMiddleware: jest.fn((handler) => handler),
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

describe('middleware production debug/test gate', () => {
  const originalVercelEnv = process.env.VERCEL_ENV;

  afterEach(() => {
    if (originalVercelEnv === undefined) {
      delete process.env.VERCEL_ENV;
    } else {
      process.env.VERCEL_ENV = originalVercelEnv;
    }

    jest.resetModules();
  });

  it.each([
    '/debug-auth',
    '/debug-login',
    '/debug',
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
    const { default: middleware, shouldBlockProductionDebugRoute } = await import('../middleware');
    const auth = { protect: jest.fn() };
    const request = new NextRequest(`https://logyourbody.com${pathname}`);

    expect(shouldBlockProductionDebugRoute(pathname)).toBe(true);

    const response = await middleware(auth, request);

    expect(response?.status).toBe(404);
    expect(response?.headers.get('Cache-Control')).toBe('no-store');
    expect(auth.protect).not.toHaveBeenCalled();
  });

  it('leaves debug routes available outside production deployments', async () => {
    process.env.VERCEL_ENV = 'preview';
    const { default: middleware, shouldBlockProductionDebugRoute } = await import('../middleware');
    const auth = { protect: jest.fn() };
    const request = new NextRequest('https://preview.logyourbody.com/api/test-openai');

    expect(shouldBlockProductionDebugRoute('/api/test-openai')).toBe(false);

    const response = await middleware(auth, request);

    expect(response).toBeUndefined();
    expect(auth.protect).not.toHaveBeenCalled();
  });

  it('keeps normal protected routes behind Clerk auth in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockProductionDebugRoute } = await import('../middleware');
    const auth = { protect: jest.fn() };
    const request = new NextRequest('https://logyourbody.com/dashboard');

    expect(shouldBlockProductionDebugRoute('/dashboard')).toBe(false);

    const response = await middleware(auth, request);

    expect(response).toBeUndefined();
    expect(auth.protect).toHaveBeenCalledTimes(1);
  });

  it('keeps normal public routes reachable in production', async () => {
    process.env.VERCEL_ENV = 'production';
    const { default: middleware, shouldBlockProductionDebugRoute } = await import('../middleware');
    const auth = { protect: jest.fn() };
    const request = new NextRequest('https://logyourbody.com/about');

    expect(shouldBlockProductionDebugRoute('/about')).toBe(false);

    const response = await middleware(auth, request);

    expect(response).toBeUndefined();
    expect(auth.protect).not.toHaveBeenCalled();
  });
});
