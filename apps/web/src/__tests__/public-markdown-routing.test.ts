/**
 * @jest-environment node
 */
import { NextRequest } from 'next/server';
import {
  getRewrittenUrl,
  unstable_getResponseFromNextConfig,
  unstable_doesMiddlewareMatch,
} from 'next/experimental/testing/server';
import middleware, { config as middlewareConfig } from '@/middleware';
import nextConfig from '../../next.config';
import { GET, HEAD } from '@/app/api/marketing/markdown-not-found/route';
import {
  PUBLIC_MARKDOWN_GATE,
  PUBLIC_MARKDOWN_HEADER,
  publicMarkdownEnabled,
} from '@/lib/marketing/public-markdown';
import { logYourBody } from '@jovieinc/product-registry';

const originalFetch = globalThis.fetch;
const originalEnvironment = {
  key: process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY,
  tier: process.env.NEXT_PUBLIC_STATSIG_ENV_TIER,
  vercel: process.env.VERCEL_ENV,
  waitlist: process.env.NEXT_PUBLIC_LYB_WAITLIST_V2,
};
const fetchMock = jest.fn();
function request(path = '/', accept = 'text/markdown', extra: HeadersInit = {}) {
  return new NextRequest(logYourBody.links.home + path, {
    headers: { Accept: accept, ...extra },
  });
}
function forwardedHeaders(response: Response, original: NextRequest): Headers {
  const headers = new Headers(original.headers);
  const names = response.headers.get('x-middleware-override-headers')?.split(',') ?? [];
  for (const name of Array.from(headers.keys())) {
    if (!names.includes(name)) headers.delete(name);
  }
  for (const name of names) {
    const value = response.headers.get('x-middleware-request-' + name);
    if (value !== null) headers.set(name, value);
  }
  return headers;
}

beforeEach(() => {
  process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY = 'client-synthetic-test-key';
  process.env.NEXT_PUBLIC_STATSIG_ENV_TIER = 'production';
  process.env.VERCEL_ENV = 'production';
  delete process.env.NEXT_PUBLIC_LYB_WAITLIST_V2;
  fetchMock
    .mockReset()
    .mockImplementation(async () => Response.json({ name: PUBLIC_MARKDOWN_GATE, value: true }));
  globalThis.fetch = fetchMock;
});
afterAll(() => {
  globalThis.fetch = originalFetch;
  const values = {
    NEXT_PUBLIC_STATSIG_CLIENT_KEY: originalEnvironment.key,
    NEXT_PUBLIC_STATSIG_ENV_TIER: originalEnvironment.tier,
    VERCEL_ENV: originalEnvironment.vercel,
    NEXT_PUBLIC_LYB_WAITLIST_V2: originalEnvironment.waitlist,
  };
  for (const [name, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

it('serves canonical homepage content and typed/no-store Markdown only after a real positive gate result', async () => {
  const response = await middleware(
    request('/', 'text/markdown', { Cookie: 'private=do-not-send' }),
  );
  expect(response.status).toBe(200);
  expect(response.headers.get('Content-Type')).toBe('text/markdown; charset=utf-8');
  expect(response.headers.get('Vary')).toBe('Accept');
  expect(response.headers.get('Cache-Control')).toBe('private, no-store');
  const body = await response.text();
  expect(body).toContain(logYourBody.brand.promise);
  expect(body).toContain(logYourBody.links.support);
  expect(body).not.toContain('free trial');
  expect(body).not.toContain('<html');
  const [url, options] = fetchMock.mock.calls[0];
  expect(url).toBe(logYourBody.endpoints.vendor.statsig.gateEvaluationUrl);
  const payload = JSON.parse(options.body);
  expect(Object.keys(payload)).toEqual(['gateName', 'user']);
  expect(payload.gateName).toBe(PUBLIC_MARKDOWN_GATE);
  expect(Object.keys(payload.user).sort()).toEqual(['statsigEnvironment', 'userID']);
  expect(payload.user.statsigEnvironment).toEqual({ tier: 'production' });
  expect(payload.user.userID).toMatch(/^[a-f0-9-]{36}$/);
  expect(JSON.stringify(options)).not.toContain('do-not-send');
});

it.each([undefined, 'text/html', '*/*', 'text/markdown;q=0', 'text/html;q=1,text/markdown;q=0.2'])(
  'preserves ordinary HTML preference %s without calling Statsig',
  async (accept) => {
    const req = request();
    if (accept === undefined) req.headers.delete('Accept');
    else req.headers.set('Accept', accept);
    const response = await middleware(req);
    expect(response.headers.get('x-middleware-next')).toBe('1');
    expect(response.headers.get('Vary')).toContain('Accept');
    expect(response.headers.get('Content-Type')).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  },
);

it.each([false, null, 'true', {}, { name: 'another_gate', value: true }])(
  'fails closed for a missing/invalid gate decision %s',
  async (value) => {
    const decision = typeof value === 'boolean' ? { name: PUBLIC_MARKDOWN_GATE, value } : value;
    fetchMock.mockResolvedValueOnce(Response.json(decision));
    const req = request('/not-a-real-public-page', 'text/markdown', {
      [PUBLIC_MARKDOWN_HEADER]: '1',
    });
    const response = await middleware(req);
    const forwarded = forwardedHeaders(response, req);
    expect(forwarded.has(PUBLIC_MARKDOWN_HEADER)).toBe(false);
    const rewrite = await unstable_getResponseFromNextConfig({
      url: req.url,
      nextConfig,
      headers: Object.fromEntries(forwarded),
    });
    expect(getRewrittenUrl(rewrite)).toBeNull();
  },
);

it('leaves original routing in place when gate configuration is absent or production tier is mismatched', async () => {
  delete process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY;
  expect(await publicMarkdownEnabled()).toBe(false);
  process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY = 'client-synthetic-test-key';
  process.env.NEXT_PUBLIC_STATSIG_ENV_TIER = 'development';
  expect(await publicMarkdownEnabled()).toBe(false);
  expect(fetchMock).not.toHaveBeenCalled();
});

it('fails closed on an HTTP error, malformed JSON, or network failure', async () => {
  fetchMock.mockResolvedValueOnce(new Response('', { status: 503 }));
  expect(await publicMarkdownEnabled()).toBe(false);
  fetchMock.mockResolvedValueOnce(new Response('not JSON'));
  expect(await publicMarkdownEnabled()).toBe(false);
  fetchMock.mockRejectedValueOnce(new Error('fixture network error'));
  expect(await publicMarkdownEnabled()).toBe(false);
});

it('bounds a hung gate request and keeps HTML fallback available', async () => {
  jest.useFakeTimers();
  fetchMock.mockImplementationOnce(
    (_url, options) =>
      new Promise((_resolve, reject) => {
        options.signal.addEventListener('abort', () => reject(new Error('aborted')), {
          once: true,
        });
      }),
  );
  const result = publicMarkdownEnabled();
  await jest.advanceTimersByTimeAsync(300);
  expect(await result).toBe(false);
  jest.useRealTimers();
});

it('routes only a negotiated unmatched path through the real Next fallback matcher, retaining status404', async () => {
  const req = request('/no-such-public-page/nested?private=never-echo');
  const middlewareResponse = await middleware(req);
  const forwarded = forwardedHeaders(middlewareResponse, req);
  expect(forwarded.get(PUBLIC_MARKDOWN_HEADER)).toBe('1');
  const configResponse = await unstable_getResponseFromNextConfig({
    url: req.url,
    nextConfig,
    headers: Object.fromEntries(forwarded),
  });
  expect(new URL(getRewrittenUrl(configResponse)!).pathname).toBe(
    '/api/marketing/markdown-not-found',
  );
  const response = GET(new Request(getRewrittenUrl(configResponse)!, { headers: forwarded }));
  expect(response.status).toBe(404);
  expect(response.headers.get('Content-Type')).toBe('text/markdown; charset=utf-8');
  expect(response.headers.get('Vary')).toBe('Accept');
  expect(response.headers.get('Cache-Control')).toBe('private, no-store');
  const body = await response.text();
  expect(body).toContain('Page not found');
  expect(body).toContain(logYourBody.links.home);
  expect(body).not.toContain('never-echo');
  // The framework utility matches config only; route precedence is asserted
  // by fallback placement and still needs a real preview HTTP receipt.
  const rewrites = await nextConfig.rewrites!();
  expect(Array.isArray(rewrites)).toBe(false);
  if (Array.isArray(rewrites)) throw new Error('Expected phased rewrites');
  expect(rewrites.afterFiles).toEqual([
    {
      source: '/.well-known/oauth-protected-resource/api/mcp',
      destination: '/api/mcp/oauth-protected-resource',
    },
    {
      source: '/.well-known/oauth-protected-resource',
      destination: '/api/mcp/oauth-protected-resource',
    },
  ]);
  expect(rewrites.fallback).toHaveLength(1);
});

it.each([
  '/api/mcp',
  '/api/auth/session',
  '/dashboard',
  '/signin',
  '/.well-known/oauth-protected-resource',
])('does not attach Markdown routing to reserved/auth/API path %s', async (path) => {
  const req = request(path, 'text/markdown', { [PUBLIC_MARKDOWN_HEADER]: '1' });
  const response = await middleware(req);
  expect(fetchMock).not.toHaveBeenCalled();
  if (response.status === 307) return;
  expect(forwardedHeaders(response, req).has(PUBLIC_MARKDOWN_HEADER)).toBe(false);
});

it.each([
  '/favicon.ico',
  '/_next/static/test.js',
  '/_next/image',
  '/missing.svg',
  '/missing/photo.png',
])('cannot forge a fallback through a path skipped by middleware: %s', async (path) => {
  expect(
    unstable_doesMiddlewareMatch({
      config: middlewareConfig,
      url: logYourBody.links.home + path,
    }),
  ).toBe(false);
  const response = await unstable_getResponseFromNextConfig({
    url: logYourBody.links.home + path,
    nextConfig,
    headers: { [PUBLIC_MARKDOWN_HEADER]: '1' },
  });
  expect(getRewrittenUrl(response)).toBeNull();
});

it('keeps HEAD bodyless and denies direct calls to the internal 404 handler', async () => {
  const head = await middleware(
    new NextRequest(logYourBody.links.home + '/', {
      method: 'HEAD',
      headers: { Accept: 'text/markdown' },
    }),
  );
  expect(head.status).toBe(200);
  expect(await head.text()).toBe('');
  const missing = HEAD(
    new Request(logYourBody.links.home + '/api/marketing/markdown-not-found', {
      method: 'HEAD',
      headers: { [PUBLIC_MARKDOWN_HEADER]: '1' },
    }),
  );
  expect(missing.status).toBe(404);
  expect(await missing.text()).toBe('');
  const direct = request('/api/marketing/markdown-not-found', 'text/markdown', {
    [PUBLIC_MARKDOWN_HEADER]: '1',
  });
  const forwarding = await middleware(direct);
  const denied = GET(new Request(direct.url, { headers: forwardedHeaders(forwarding, direct) }));
  expect(denied.status).toBe(404);
  expect(denied.headers.get('Content-Type')).toBeNull();
});

it('does not negotiate an RSC/prefetch or unsafe-method request', async () => {
  for (const req of [
    request('/', 'text/markdown', { RSC: '1' }),
    request('/', 'text/markdown', { 'next-router-prefetch': '1' }),
    new NextRequest(logYourBody.links.home + '/', {
      method: 'POST',
      headers: { Accept: 'text/markdown' },
    }),
  ]) {
    const response = await middleware(req);
    expect(response.headers.get('Content-Type')).toBeNull();
  }
  expect(fetchMock).not.toHaveBeenCalled();
});
