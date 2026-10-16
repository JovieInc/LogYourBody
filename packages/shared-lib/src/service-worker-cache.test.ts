import { readFileSync } from 'node:fs';
import { setImmediate } from 'node:timers/promises';
import { runInNewContext } from 'node:vm';
import { describe, expect, it, vi } from 'vitest';

const { Request, Response, URL } = globalThis;
const origin = 'https://app.example';
const source = readFileSync(new URL('../../../apps/web/public/sw.js', import.meta.url), 'utf8');
type Input = string | Request;
type WorkerEvent = {
  request?: Request;
  origin?: string;
  data?: { type: string };
  waitUntil: (promise: Promise<unknown>) => void;
  respondWith: (promise: Promise<Response>) => void;
};

function worker() {
  const handlers = new Map<string, (event: WorkerEvent) => void>();
  const stores = new Map<string, Map<string, Response>>();
  const key = (input: Input) => new URL(typeof input === 'string' ? input : input.url, origin).href;
  const network = vi.fn<(input: Input, options?: object) => Promise<Response>>(
    async () => new Response('public asset'),
  );
  const put = vi.fn(async (store: Map<string, Response>, input: Input, response: Response) => {
    store.set(key(input), response.clone());
  });
  const caches = {
    keys: async () => [...stores.keys()],
    delete: async (name: string) => stores.delete(name),
    open: async (name: string) => {
      if (!stores.has(name)) stores.set(name, new Map());
      const store = stores.get(name)!;
      return {
        match: async (input: Input) => store.get(key(input))?.clone(),
        put: (input: Input, response: Response) => put(store, input, response),
        addAll: async (inputs: Input[]) => {
          for (const input of inputs) await put(store, input, await network(input));
        },
      };
    },
    match: async (input: Input) => {
      for (const store of stores.values()) {
        const response = store.get(key(input));
        if (response) return response.clone();
      }
    },
  };
  const self = {
    location: { origin },
    addEventListener: (name: string, handler: (event: WorkerEvent) => void) =>
      handlers.set(name, handler),
    skipWaiting: vi.fn(async () => undefined),
    clients: { claim: vi.fn(async () => undefined) },
    registration: { update: vi.fn(async () => undefined) },
  };
  runInNewContext(source, { self, caches, fetch: network, Request, Response, URL, console });
  async function dispatch(name: string, fields: Partial<WorkerEvent> = {}) {
    const pending: Promise<unknown>[] = [];
    let response: Promise<Response> | undefined;
    handlers.get(name)!({
      ...fields,
      waitUntil: (promise) => pending.push(promise),
      respondWith: (promise) => {
        response = Promise.resolve(promise);
      },
    });
    const result = response ? await response : undefined;
    await Promise.all(pending);
    // Also observe the old worker's untracked cache writes when proving the regression.
    await setImmediate();
    return result;
  }
  return { dispatch, network, put, caches, stores, self };
}

function request(path: string, options: RequestInit = {}) {
  return new Request(new URL(path, origin), options);
}

describe('service-worker privacy boundary', () => {
  it.each(['/api/measurements', '/api/export.json', '/account', '/history'])(
    'never persists private responses for %s',
    async (path) => {
      const w = worker();
      w.network.mockImplementation(
        async () =>
          new Response('private measurements', {
            headers: { 'cache-control': 'private, no-store', 'content-type': 'text/html' },
          }),
      );
      await w.dispatch('fetch', { request: request(path, { headers: { accept: 'text/html' } }) });
      expect(w.put).not.toHaveBeenCalled();
    },
  );

  it('does not replay a prior account page from any legacy cache when offline', async () => {
    const w = worker();
    await (
      await w.caches.open('logyourbody-v2')
    ).put(request('/account'), new Response('Alice private data'));
    await w.dispatch('install');
    w.network.mockRejectedValue(new Error('offline'));
    const navigation = request('/account');
    Object.defineProperty(navigation, 'mode', { value: 'navigate' });
    expect(await (await w.dispatch('fetch', { request: navigation }))!.text()).toBe('public asset');
  });

  it('purges owned legacy caches before claiming clients and preserves unrelated caches', async () => {
    const w = worker();
    await w.caches.open('logyourbody-v1');
    await w.caches.open('logyourbody-v2');
    await w.caches.open('another-application');
    await w.dispatch('install');
    w.self.clients.claim.mockImplementation(async () => {
      expect(await w.caches.keys()).not.toContain('logyourbody-v2');
    });
    await w.dispatch('activate');
    expect(await w.caches.keys()).toEqual(expect.arrayContaining(['another-application']));
    expect(await w.caches.keys()).not.toContain('logyourbody-v1');
    expect(await w.caches.keys()).not.toContain('logyourbody-v2');
    expect(w.self.clients.claim).toHaveBeenCalledOnce();
  });

  it.each([
    'https://app.example.attacker.example/file.js',
    '/api/photo.png',
    '/private/photo.jpg',
    '/_next/image?url=private-photo',
    '/favicon.ico?token=secret',
  ])('does not intercept non-public asset %s', async (path) => {
    const w = worker();
    expect(await w.dispatch('fetch', { request: request(path) })).toBeUndefined();
    expect(w.network).not.toHaveBeenCalled();
    expect(w.put).not.toHaveBeenCalled();
  });

  it('keeps the offline shell and build assets available without sending credentials', async () => {
    const w = worker();
    await w.dispatch('install');
    await w.dispatch('activate');
    const asset = request('/_next/static/chunks/abc.js');
    expect(await (await w.dispatch('fetch', { request: asset }))!.text()).toBe('public asset');
    expect(
      w.network.mock.calls.every(
        ([input, options]) =>
          (options as { credentials?: string } | undefined)?.credentials === 'omit' ||
          (input instanceof Request && input.credentials === 'omit'),
      ),
    ).toBe(true);
    w.network.mockRejectedValue(new Error('offline'));
    expect(await (await w.dispatch('fetch', { request: asset }))!.text()).toBe('public asset');
  });

  it.each(['private, max-age=60', 'public, no-store', 'no-cache'])(
    'honors %s even on a public asset path',
    async (policy) => {
      const w = worker();
      w.network.mockImplementation(
        async () => new Response('not cacheable', { headers: { 'cache-control': policy } }),
      );
      expect(
        await (await w.dispatch('fetch', {
          request: request('/_next/static/chunks/abc.js'),
        }))!.text(),
      ).toBe('not cacheable');
      expect(w.put).not.toHaveBeenCalled();
    },
  );

  it.each(['Cookie', 'Authorization', '*'])(
    'does not cache responses varying on %s',
    async (vary) => {
      const w = worker();
      w.network.mockImplementation(async () => new Response('variant', { headers: { vary } }));
      await w.dispatch('fetch', { request: request('/favicon.ico') });
      expect(w.put).not.toHaveBeenCalled();
    },
  );

  it('ignores failed and redirected asset responses', async () => {
    const w = worker();
    w.network.mockImplementationOnce(async () => new Response('failure', { status: 500 }));
    await w.dispatch('fetch', { request: request('/favicon.ico') });
    const redirected = new Response('sign in');
    Object.defineProperty(redirected, 'redirected', { value: true });
    w.network.mockResolvedValueOnce(redirected);
    await w.dispatch('fetch', { request: request('/favicon.ico') });
    expect(w.put).not.toHaveBeenCalled();
  });

  it('leaves authenticated and explicit no-store asset requests to the network', async () => {
    const w = worker();
    for (const options of [
      { headers: { authorization: 'Bearer test' } },
      { cache: 'no-store' as const },
    ]) {
      expect(
        await w.dispatch('fetch', { request: request('/favicon.ico', options) }),
      ).toBeUndefined();
    }
    expect(w.network).not.toHaveBeenCalled();
  });

  it('does not replace a successful network response when cache storage fails', async () => {
    const w = worker();
    w.caches.open = vi.fn().mockRejectedValue(new Error('storage unavailable'));
    expect(await (await w.dispatch('fetch', { request: request('/favicon.ico') }))!.text()).toBe(
      'public asset',
    );
  });

  it('returns an explicit offline navigation response when the shell cache is unavailable', async () => {
    const w = worker();
    w.network.mockRejectedValue(new Error('offline'));
    w.caches.open = vi.fn().mockRejectedValue(new Error('storage unavailable'));
    const navigation = request('/account');
    Object.defineProperty(navigation, 'mode', { value: 'navigate' });
    expect((await w.dispatch('fetch', { request: navigation }))?.status).toBe(503);
  });

  it('only accepts update commands from same-origin clients', async () => {
    const w = worker();
    for (const type of ['SKIP_WAITING', 'CHECK_UPDATE']) {
      await w.dispatch('message', { origin: `${origin}.attacker.example`, data: { type } });
      await w.dispatch('message', { data: { type } });
    }
    expect(w.self.skipWaiting).not.toHaveBeenCalled();
    expect(w.self.registration.update).not.toHaveBeenCalled();
    await w.dispatch('message', { origin, data: { type: 'SKIP_WAITING' } });
    await w.dispatch('message', { origin, data: { type: 'CHECK_UPDATE' } });
    expect(w.self.skipWaiting).toHaveBeenCalledOnce();
    expect(w.self.registration.update).toHaveBeenCalledOnce();
  });
});
