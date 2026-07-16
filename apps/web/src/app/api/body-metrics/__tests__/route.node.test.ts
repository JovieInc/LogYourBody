/** @jest-environment node */

import { NextRequest } from 'next/server';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { POST } from '../route';

jest.mock('@/lib/neon/body-metrics-adapter', () => ({ neonBodyMetrics: { upsert: jest.fn() } }));
jest.mock('@/lib/ports/server-auth-runtime', () => ({ getServerAuthSession: jest.fn() }));

const mockedMetrics = jest.mocked(neonBodyMetrics);
const mockedAuth = jest.mocked(getServerAuthSession);

function request(body: unknown) {
  return new NextRequest('http://localhost/api/body-metrics', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('/api/body-metrics', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedAuth.mockResolvedValue({ userId: 'jovie-user-1', getToken: jest.fn() });
  });

  it('rejects unauthenticated writes', async () => {
    mockedAuth.mockResolvedValue({ userId: null, getToken: jest.fn() });
    expect((await POST(request({ date: '2026-07-15' }))).status).toBe(401);
  });

  it('validates and maps the app contract to the Neon port', async () => {
    mockedMetrics.upsert.mockResolvedValue({ id: 'metric-1' } as never);
    const response = await POST(
      request({
        date: '2026-07-15',
        weight: 80,
        weightUnit: 'kg',
        bodyFatPercentage: 18,
        bodyFatMethod: 'dexa',
        dataSource: 'bodyspec_dexa',
      }),
    );
    expect(response.status).toBe(201);
    expect(mockedMetrics.upsert).toHaveBeenCalledWith('jovie-user-1', {
      date: '2026-07-15',
      weight: 80,
      weight_unit: 'kg',
      body_fat_percentage: 18,
      body_fat_method: 'dexa',
      muscle_mass: null,
      waist: null,
      neck: null,
      hip: null,
      notes: null,
      photo_url: null,
      data_source: 'bodyspec_dexa',
      source_metadata: {},
    });
  });
});
