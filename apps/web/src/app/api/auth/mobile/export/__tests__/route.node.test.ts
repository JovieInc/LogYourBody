/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { GET, POST } from '../route';

jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));
jest.mock('@/lib/neon/body-metrics-adapter', () => ({
  neonBodyMetrics: { list: jest.fn() },
}));
jest.mock('@/lib/neon/native-product-records-adapter', () => ({
  neonNativeProductRecords: { listAll: jest.fn() },
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { getUser: jest.fn() },
}));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);
const mockedMetrics = jest.mocked(neonBodyMetrics);
const mockedRecords = jest.mocked(neonNativeProductRecords);
const mockedDirectory = jest.mocked(neonUserDirectory);

function request(method: 'GET' | 'POST', token?: string) {
  return new NextRequest('http://localhost/api/auth/mobile/export', {
    method,
    headers: token ? { authorization: `Bearer ${token}` } : undefined,
  });
}

describe('/api/auth/mobile/export', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects missing bearer tokens and cookies before reading Neon', async () => {
    expect((await GET(request('GET'))).status).toBe(401);
    expect(mockedDirectory.getUser).not.toHaveBeenCalled();
  });

  it('accepts the first-party session cookie when no bearer token is present', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedDirectory.getUser.mockResolvedValue({ subject: 'owner-a' } as never);
    mockedMetrics.list.mockResolvedValue([]);
    mockedRecords.listAll.mockResolvedValue({
      daily_metrics: [],
      glp1_medications: [],
      glp1_dose_logs: [],
      dexa_results: [],
      progress_photos: [],
    } as never);

    const response = await GET(
      new NextRequest('http://localhost/api/auth/mobile/export', {
        headers: { cookie: 'lyb_access_token=cookie-a' },
      }),
    );
    expect(response.status).toBe(200);
    expect(mockedFetchUserInfo).toHaveBeenCalledWith('cookie-a');
    expect(mockedDirectory.getUser).toHaveBeenCalledWith('owner-a');
  });

  it('dumps the authenticated subject Neon rows without a Supabase path', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedDirectory.getUser.mockResolvedValue({ subject: 'owner-a', email: 'a@example.com' } as never);
    mockedMetrics.list.mockResolvedValue([{ id: 'metric-1' }] as never);
    mockedRecords.listAll.mockResolvedValue({
      daily_metrics: [{ id: 'daily-1' }],
      glp1_medications: [],
      glp1_dose_logs: [],
      dexa_results: [],
      progress_photos: [],
    } as never);

    const response = await POST(request('POST', 'access-a'));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      version: 1,
      subject: 'owner-a',
      profile: { subject: 'owner-a' },
      body_metrics: [{ id: 'metric-1' }],
      daily_metrics: [{ id: 'daily-1' }],
    });
    expect(mockedMetrics.list).toHaveBeenCalledWith('owner-a', 100);
    expect(mockedRecords.listAll).toHaveBeenCalledWith('owner-a');
  });
});
