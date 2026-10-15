/** @jest-environment node */
import { NextRequest, NextResponse } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { canvasHandlers } from '../../../auth/mobile/training/v1/dependencies';
import { httpCanvasClient } from '@/lib/training/mesocycle-canvas-client';
import { readCanvasLedger } from '@/lib/training/mesocycle-canvas';
import { POST } from '../route';

jest.mock('@/lib/ports/server-auth-runtime', () => ({ getServerAuthSession: jest.fn() }));
jest.mock('../../../auth/mobile/training/v1/dependencies', () => ({
  canvasHandlers: { POST: jest.fn() },
}));

const auth = jest.mocked(getServerAuthSession);
const nativePost = jest.mocked(canvasHandlers.POST);
const url = 'https://example.test/api/training/canvas';
const previousEnv = { ...process.env };

function request(headers: Record<string, string> = {}, signal?: AbortSignal) {
  return new NextRequest(url, {
    method: 'POST',
    headers: {
      origin: 'https://example.test',
      'content-type': 'application/json',
      'x-lyb-account-subject': 'owner-A',
      ...headers,
    },
    body: JSON.stringify({ action: 'read' }),
    signal,
  });
}

beforeEach(() => {
  jest.resetAllMocks();
  process.env.LYB_MESOCYCLE_CANVAS_ENABLED = 'true';
  process.env.LYB_HYPERTROPHY_COACH_API_ENABLED = 'true';
  auth.mockResolvedValue({ userId: 'owner-A', getToken: async () => 'server-only-token' });
  nativePost.mockResolvedValue(
    NextResponse.json({ version: 1, kind: 'read' }, { headers: { 'Cache-Control': 'no-store' } }),
  );
});

afterAll(() => {
  process.env = previousEnv;
});

it('forwards the validated server credential, exact body and signal to the unchanged bearer handler', async () => {
  const incoming = request({
    authorization: 'Bearer attacker-supplied',
    cookie: 'untrusted=value',
  });
  const response = await POST(incoming);
  expect(response.status).toBe(200);
  expect(response.headers.get('Cache-Control')).toBe('no-store');
  expect(nativePost).toHaveBeenCalledTimes(1);
  const forwarded = nativePost.mock.calls[0][0];
  expect(new URL(forwarded.url).pathname).toBe('/api/auth/mobile/training/v1/canvas');
  expect(Object.fromEntries(forwarded.headers)).toEqual({
    accept: 'application/json',
    'content-type': 'application/json',
    authorization: 'Bearer server-only-token',
  });
  expect(await forwarded.json()).toEqual({ action: 'read' });
  expect(forwarded.signal.aborted).toBe(false);
  expect(JSON.stringify(await response.json())).not.toContain('server-only-token');
});

it.each(['LYB_MESOCYCLE_CANVAS_ENABLED', 'LYB_HYPERTROPHY_COACH_API_ENABLED'])(
  'keeps %s default-off before session or provider work',
  async (flag) => {
    delete process.env[flag];
    expect((await POST(request())).status).toBe(404);
    expect(auth).not.toHaveBeenCalled();
    expect(nativePost).not.toHaveBeenCalled();
  },
);

it.each(['https://foreign.test', 'null', ''])(
  'refuses nonmatching origin %s before session work',
  async (origin) => {
    expect((await POST(request({ origin }))).status).toBe(403);
    expect(auth).not.toHaveBeenCalled();
    expect(nativePost).not.toHaveBeenCalled();
  },
);

it('refuses simple form submissions', async () => {
  expect((await POST(request({ 'content-type': 'text/plain' }))).status).toBe(415);
  expect(nativePost).not.toHaveBeenCalled();
});

it('fails closed when signed out without asking for or forwarding a credential', async () => {
  const getToken = jest.fn(async () => 'unexpected');
  auth.mockResolvedValue({ userId: null, getToken });
  expect((await POST(request())).status).toBe(401);
  expect(getToken).not.toHaveBeenCalled();
  expect(nativePost).not.toHaveBeenCalled();
});

it('refuses a switched account instead of applying an old page action to the new owner', async () => {
  const getToken = jest.fn(async () => 'owner-B-token');
  auth.mockResolvedValue({ userId: 'owner-B', getToken });
  expect((await POST(request())).status).toBe(409);
  expect(getToken).not.toHaveBeenCalled();
  expect(nativePost).not.toHaveBeenCalled();
});

it.each([null, '', 'invalid\r\ncredential'])(
  'does not forward a missing or invalid server token',
  async (token) => {
    auth.mockResolvedValue({ userId: 'owner-A', getToken: async () => token });
    expect((await POST(request())).status).toBe(401);
    expect(nativePost).not.toHaveBeenCalled();
  },
);

it('does not dispatch after abort while the existing session port is loading', async () => {
  const controller = new AbortController();
  let release!: (value: Awaited<ReturnType<typeof getServerAuthSession>>) => void;
  auth.mockReturnValue(
    new Promise((resolve) => {
      release = resolve;
    }),
  );
  const pending = POST(request({}, controller.signal));
  controller.abort();
  release({ userId: 'owner-A', getToken: async () => 'server-only-token' });
  expect((await pending).status).toBe(499);
  expect(nativePost).not.toHaveBeenCalled();
});

it('does not replay an expired bearer or mutate native error responses', async () => {
  nativePost.mockResolvedValue(
    NextResponse.json({ version: 1, error: 'unauthorized' }, { status: 401 }),
  );
  expect((await POST(request())).status).toBe(401);
  expect(nativePost).toHaveBeenCalledTimes(1);
});

it('connects the actual browser client to this adapter without exposing a bearer to JavaScript', async () => {
  const fetchImpl = jest.fn(async (_input, init) => {
    expect(new Headers(init?.headers).has('authorization')).toBe(false);
    expect(init?.credentials).toBe('same-origin');
    return POST(
      new NextRequest(url, {
        ...init,
        headers: {
          ...Object.fromEntries(new Headers(init?.headers)),
          origin: 'https://example.test',
        },
      }),
    );
  });
  const client = httpCanvasClient(fetchImpl as typeof fetch, { subject: 'owner-A' });
  await client.read();
  expect(fetchImpl).toHaveBeenCalledTimes(1);
  expect(fetchImpl.mock.calls[0][0]).toBe('/api/training/canvas');
  expect(nativePost.mock.calls[0][0].headers.get('authorization')).toBe('Bearer server-only-token');
});

it('makes no browser request without a captured signed-in subject or after abort', async () => {
  const fetchImpl = jest.fn();
  await httpCanvasClient(fetchImpl as typeof fetch).read();
  const controller = new AbortController();
  controller.abort();
  await httpCanvasClient(fetchImpl as typeof fetch, {
    subject: 'owner-A',
    signal: controller.signal,
  }).submit('old draft');
  expect(fetchImpl).not.toHaveBeenCalled();
});

it('propagates a later abort to the native request without replaying it', async () => {
  const controller = new AbortController();
  await POST(request({}, controller.signal));
  const forwarded = nativePost.mock.calls[0][0];
  controller.abort();
  expect(forwarded.signal.aborted).toBe(true);
  expect(nativePost).toHaveBeenCalledTimes(1);
});

it('discards a late browser readback after its captured session is aborted', async () => {
  const controller = new AbortController();
  let finish!: (response: Response) => void;
  const fetchImpl = jest.fn(
    () =>
      new Promise<Response>((resolve) => {
        finish = resolve;
      }),
  );
  const client = httpCanvasClient(fetchImpl as typeof fetch, {
    subject: 'owner-A',
    signal: controller.signal,
  });
  const pending = client.read();
  controller.abort();
  finish(Response.json({ kind: 'read', readback: readCanvasLedger(null, 'Old account response') }));
  const result = await pending;
  expect(result.kind).toBe('missed_update');
  expect(result.readback.narration).not.toBe('Old account response');
  expect(fetchImpl).toHaveBeenCalledTimes(1);
});
