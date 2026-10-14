/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { POST } from '../route';

jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { captureAccountAdmission: jest.fn() },
}));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);
const mockedCapture = jest.mocked(neonUserDirectory.captureAccountAdmission);
const fixtureOwner = { subject: 'owner-a', ownerId: '11111111-1111-4111-8111-111111111111' };

const r2Env = {
  CLOUDFLARE_ACCOUNT_ID: 'a1b2c3d4e5f607182930aabbccddeeff',
  CLOUDFLARE_R2_ACCESS_KEY_ID: 'AKIAFIXTUREACCESS',
  CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYFIXTUREKEY',
  CLOUDFLARE_R2_BUCKET: 'lyb-progress-photos',
  CLOUDFLARE_R2_PUBLIC_BASE_URL: 'https://photos.logyourbody.com',
};

const originalEnv = { ...r2Env };

function request(token?: string, body?: unknown) {
  return new NextRequest('http://localhost/api/auth/mobile/photos', {
    method: 'POST',
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

function clearR2Env() {
  for (const key of Object.keys(r2Env)) {
    delete process.env[key];
  }
}

function setR2Env() {
  Object.assign(process.env, r2Env);
}

describe('/api/auth/mobile/photos', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedCapture.mockReset().mockResolvedValue(fixtureOwner);
    for (const key of Object.keys(r2Env) as (keyof typeof r2Env)[]) {
      originalEnv[key] = process.env[key];
    }
    clearR2Env();
  });

  afterEach(() => {
    clearR2Env();
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it('rejects missing bearer tokens', async () => {
    const response = await POST(request());
    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({ error: 'unauthorized' });
  });

  it('fails closed when Cloudflare R2 is not configured on the first-party API', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    const response = await POST(request('access-a'));
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({
      error: 'photo_store_unavailable',
      message: expect.stringContaining('Cloudflare R2'),
    });
  });

  it('rejects an authenticated ticket request with an unsafe metrics id', async () => {
    setR2Env();
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    const response = await POST(
      request('access-a', { metricsId: '../victim', contentType: 'image/jpeg' }),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({ error: 'invalid_photo_upload' });
  });

  it('returns a user-scoped Cloudflare R2 PUT ticket', async () => {
    setR2Env();
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    const response = await POST(
      request('access-a', {
        metricsId: 'metric-owned',
        contentType: 'image/jpeg',
        byteSize: 2048,
      }),
    );
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.uploadMethod).toBe('PUT');
    expect(body.uploadHeaders).toEqual({ 'content-type': 'image/jpeg' });
    expect(body.objectKey).toMatch(
      /^progress-photos\/owner-a\/accounts\/11111111-1111-4111-8111-111111111111\/metric-owned_\d+\.jpg$/,
    );
    expect(body.storagePath).toBe(body.objectKey);
    expect(body.photoUrl).toBe(`https://photos.logyourbody.com/${body.objectKey}`);
    const upload = new URL(body.uploadUrl);
    expect(upload.host).toBe('a1b2c3d4e5f607182930aabbccddeeff.r2.cloudflarestorage.com');
    expect(upload.pathname).toBe(`/lyb-progress-photos/${body.objectKey}`);
    expect(upload.searchParams.get('X-Amz-SignedHeaders')).toBe('content-type;host');
    expect(String(body.uploadUrl)).not.toContain(r2Env.CLOUDFLARE_R2_SECRET_ACCESS_KEY);
  });

  it('does not issue upload tickets for an absent product account', async () => {
    setR2Env();
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedCapture.mockResolvedValue(null);
    const response = await POST(request('access-a', { metricsId: 'metric-owned' }));
    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({ error: 'account_not_found' });
    expect(mockedCapture).toHaveBeenCalledTimes(1);
  });

  it.each([null, { ...fixtureOwner, ownerId: '22222222-2222-4222-8222-222222222222' }])(
    'rejects a held request when its captured product account changes',
    async (replacement) => {
      setR2Env();
      mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
      let resumeBody!: (value: unknown) => void;
      let signalBodyEntered!: () => void;
      const bodyEntered = new Promise<void>((resolve) => {
        signalBodyEntered = resolve;
      });
      const held = request('access-a');
      jest.spyOn(held, 'json').mockImplementation(
        () =>
          new Promise((resolve) => {
            resumeBody = resolve;
            signalBodyEntered();
          }),
      );
      const result = POST(held);
      await bodyEntered;
      expect(mockedCapture).toHaveBeenCalledTimes(1);
      mockedCapture.mockResolvedValue(replacement);
      resumeBody({ metricsId: 'metric-owned' });
      const response = await result;
      expect(response.status).toBe(409);
      await expect(response.json()).resolves.toEqual({ error: 'account_changed' });
    },
  );
});
