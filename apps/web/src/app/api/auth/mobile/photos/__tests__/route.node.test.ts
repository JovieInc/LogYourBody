/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { POST } from '../route';

jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);

function request(token?: string) {
  return new NextRequest('http://localhost/api/auth/mobile/photos', {
    method: 'POST',
    headers: token ? { authorization: `Bearer ${token}` } : undefined,
  });
}

describe('/api/auth/mobile/photos', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects missing bearer tokens', async () => {
    const response = await POST(request());
    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({ error: 'unauthorized' });
  });

  it('fails closed when Cloudinary is not configured on the first-party API', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    const response = await POST(request('access-a'));
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({
      error: 'photo_store_unavailable',
    });
  });
});
