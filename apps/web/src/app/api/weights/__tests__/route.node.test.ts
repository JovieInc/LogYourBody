/** @jest-environment node */

import type { NextRequest } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { GET, POST } from '../route';

jest.mock('@/lib/ports/server-auth-runtime', () => ({ getServerAuthSession: jest.fn() }));
jest.mock('@/lib/neon/body-metrics-adapter', () => ({
  neonBodyMetrics: { list: jest.fn(), upsert: jest.fn() },
}));

const mockedAuth = jest.mocked(getServerAuthSession);
const mockedMetrics = jest.mocked(neonBodyMetrics);
const getToken = jest.fn();

function createJsonRequest(body: unknown) {
  return { json: jest.fn().mockResolvedValue(body) } as unknown as NextRequest;
}

describe('/api/weights', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers().setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    mockedAuth.mockResolvedValue({ userId: 'jovie-user-1', getToken });
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('rejects unauthenticated GET requests before querying Neon', async () => {
    mockedAuth.mockResolvedValue({ userId: null, getToken });
    const response = await GET({} as NextRequest);
    expect(response.status).toBe(401);
    expect(mockedMetrics.list).not.toHaveBeenCalled();
  });

  it('returns the authenticated user metrics from Neon', async () => {
    const weights = [
      { id: 'metric-1', user_subject: 'jovie-user-1', date: '2026-01-02', weight: 82.2 },
    ];
    mockedMetrics.list.mockResolvedValue(weights as never);
    const response = await GET({} as NextRequest);
    await expect(response.json()).resolves.toEqual({ weights });
    expect(mockedMetrics.list).toHaveBeenCalledWith('jovie-user-1');
  });

  it('validates required weight input before writing', async () => {
    const response = await POST(createJsonRequest({ weight: '180' }));
    expect(response.status).toBe(400);
    expect(mockedMetrics.upsert).not.toHaveBeenCalled();
  });

  it('converts pounds to kilograms and upserts the metric for the session subject', async () => {
    const entry = { id: 'metric-1', weight: 81.64656, weight_unit: 'kg' };
    mockedMetrics.upsert.mockResolvedValue(entry as never);
    const response = await POST(
      createJsonRequest({ weight: '180', unit: 'lbs', notes: 'morning' }),
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true, weight: entry });
    expect(mockedMetrics.upsert).toHaveBeenCalledWith('jovie-user-1', {
      date: '2026-01-02',
      weight: 81.64656,
      weight_unit: 'kg',
      body_fat_percentage: null,
      body_fat_method: null,
      muscle_mass: null,
      waist: null,
      neck: null,
      hip: null,
      notes: 'morning',
      photo_url: null,
      data_source: 'manual',
      source_metadata: {},
    });
  });
});
