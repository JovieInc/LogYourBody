/**
 * @jest-environment node
 */
import type { NextRequest } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { createAuthenticatedDataClient } from '@/lib/ports/server-data-client';
import { GET, POST } from '../route';

jest.mock('next/server', () => ({
  NextResponse: {
    json: (data: unknown, init?: ResponseInit) => ({
      json: async () => data,
      status: init?.status ?? 200,
    }),
  },
}));

jest.mock('@/lib/ports/server-auth-runtime', () => ({
  getServerAuthSession: jest.fn(),
}));

jest.mock('@/lib/ports/server-data-client', () => ({
  createAuthenticatedDataClient: jest.fn(),
}));

function createJsonRequest(body: unknown) {
  return {
    json: jest.fn().mockResolvedValue(body),
  } as unknown as NextRequest;
}

function createGetSupabase(result: { data: unknown; error: unknown }) {
  const builder: Record<string, jest.Mock> = {};
  builder.select = jest.fn(() => builder);
  builder.eq = jest.fn(() => builder);
  builder.order = jest.fn(() => builder);
  builder.limit = jest.fn().mockResolvedValue(result);

  return {
    builder,
    client: {
      from: jest.fn(() => builder),
    },
  };
}

function createPostSupabase(result: { data: unknown; error: unknown }) {
  const builder: Record<string, jest.Mock> = {};
  builder.insert = jest.fn(() => builder);
  builder.select = jest.fn(() => builder);
  builder.single = jest.fn().mockResolvedValue(result);

  return {
    builder,
    client: {
      from: jest.fn(() => builder),
    },
  };
}

describe('/api/weights', () => {
  const getToken = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers().setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    getToken.mockResolvedValue('supabase-token');
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: 'user_123', getToken });
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('rejects unauthenticated GET requests before creating a data client', async () => {
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: null, getToken });

    const response = await GET({} as NextRequest);

    await expect(response.json()).resolves.toEqual({ error: 'Unauthorized' });
    expect(response.status).toBe(401);
    expect(createAuthenticatedDataClient).not.toHaveBeenCalled();
  });

  it('returns the latest authenticated weight entries', async () => {
    const weights = [
      { id: 'metric_2', user_id: 'user_123', date: '2026-01-02', weight: 82.2 },
      { id: 'metric_1', user_id: 'user_123', date: '2026-01-01', weight: 82.6 },
    ];
    const supabase = createGetSupabase({ data: weights, error: null });
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await GET({} as NextRequest);

    await expect(response.json()).resolves.toEqual({ weights });
    expect(response.status).toBe(200);
    expect(createAuthenticatedDataClient).toHaveBeenCalledWith(getToken);
    expect(supabase.client.from).toHaveBeenCalledWith('body_metrics');
    expect(supabase.builder.select).toHaveBeenCalledWith('*');
    expect(supabase.builder.eq).toHaveBeenCalledWith('user_id', 'user_123');
    expect(supabase.builder.order).toHaveBeenCalledWith('date', { ascending: false });
    expect(supabase.builder.limit).toHaveBeenCalledWith(30);
  });

  it('rejects POST requests missing weight or unit', async () => {
    const supabase = createPostSupabase({ data: null, error: null });
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await POST(createJsonRequest({ weight: '180' }));

    await expect(response.json()).resolves.toEqual({ error: 'Weight and unit are required' });
    expect(response.status).toBe(400);
    expect(supabase.client.from).not.toHaveBeenCalled();
  });

  it('converts pounds to kilograms before inserting a body metric', async () => {
    const insertedMetric = {
      id: 'metric_123',
      user_id: 'user_123',
      date: '2026-01-02T03:04:05.000Z',
      weight: 81.64656,
      weight_unit: 'kg',
      notes: 'morning weigh-in',
    };
    const supabase = createPostSupabase({ data: insertedMetric, error: null });
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await POST(
      createJsonRequest({ weight: '180', unit: 'lbs', notes: 'morning weigh-in' }),
    );

    await expect(response.json()).resolves.toEqual({ success: true, weight: insertedMetric });
    expect(response.status).toBe(200);
    expect(supabase.client.from).toHaveBeenCalledWith('body_metrics');
    expect(supabase.builder.insert).toHaveBeenCalledWith({
      user_id: 'user_123',
      date: '2026-01-02T03:04:05.000Z',
      weight: 81.64656,
      weight_unit: 'kg',
      notes: 'morning weigh-in',
    });
    expect(supabase.builder.select).toHaveBeenCalledWith();
    expect(supabase.builder.single).toHaveBeenCalledWith();
  });

  it('returns a 500 response when the weights query fails', async () => {
    const supabase = createGetSupabase({
      data: null,
      error: { message: 'permission denied for table body_metrics' },
    });
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await GET({} as NextRequest);

    await expect(response.json()).resolves.toEqual({ error: 'Internal server error' });
    expect(response.status).toBe(500);
    expect(console.error).toHaveBeenCalledWith('Error fetching weights:', {
      message: 'permission denied for table body_metrics',
    });
  });
});
