/**
 * @jest-environment node
 */
import { DELETE } from '../route';
import { deleteServerAuthUser, getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { createAuthenticatedDataClient } from '@/lib/ports/server-data-client';

jest.mock('next/server', () => ({
  NextResponse: {
    json: (data: unknown, init?: ResponseInit) => ({
      json: async () => data,
      status: init?.status ?? 200,
    }),
  },
}));

jest.mock('@/lib/ports/server-auth-runtime', () => ({
  deleteServerAuthUser: jest.fn(),
  getServerAuthSession: jest.fn(),
}));

jest.mock('@/lib/ports/server-data-client', () => ({
  createAuthenticatedDataClient: jest.fn(),
}));

class MockDeleteBuilder {
  constructor(
    private readonly table: string,
    private readonly failures: ReadonlyMap<string, unknown>,
    private readonly calls: string[],
  ) {}

  async eq(column: string, value: string) {
    this.calls.push(`${this.table}.${column}=${value}`);
    const error = this.failures.get(this.table);

    return error ? { error } : { error: null };
  }
}

function createMockSupabase(failures: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const failureMap = new Map(Object.entries(failures));

  return {
    calls,
    client: {
      from(table: string) {
        return {
          delete() {
            return new MockDeleteBuilder(table, failureMap, calls);
          },
        };
      },
    },
  };
}

describe('DELETE /api/auth/delete-account', () => {
  const getToken = jest.fn();
  const originalSupabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const originalSupabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.example';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key';

    getToken.mockResolvedValue('clerk-token');
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: 'user_123', getToken });
    (global.fetch as jest.Mock | undefined) = jest.fn().mockResolvedValue({
      ok: true,
      text: async () => '',
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();

    if (originalSupabaseUrl === undefined) {
      delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    } else {
      process.env.NEXT_PUBLIC_SUPABASE_URL = originalSupabaseUrl;
    }

    if (originalSupabaseAnonKey === undefined) {
      delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    } else {
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalSupabaseAnonKey;
    }
  });

  it('rejects unauthenticated deletion requests before data cleanup starts', async () => {
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: null, getToken });

    const response = await DELETE();

    await expect(response.json()).resolves.toEqual({ error: 'Unauthorized' });
    expect(response.status).toBe(401);
    expect(getToken).not.toHaveBeenCalled();
    expect(createAuthenticatedDataClient).not.toHaveBeenCalled();
    expect(deleteServerAuthUser).not.toHaveBeenCalled();
  });

  it('rejects deletion requests that cannot mint a Supabase token', async () => {
    getToken.mockResolvedValue(null);

    const response = await DELETE();

    await expect(response.json()).resolves.toEqual({ error: 'Missing authentication token' });
    expect(response.status).toBe(401);
    expect(createAuthenticatedDataClient).not.toHaveBeenCalled();
    expect(deleteServerAuthUser).not.toHaveBeenCalled();
  });

  it('does not delete the Clerk user when required data cleanup fails', async () => {
    const supabase = createMockSupabase({
      body_metrics: { message: 'permission denied for table body_metrics' },
    });
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await DELETE();

    await expect(response.json()).resolves.toEqual({
      error: 'Unable to delete all account data. Please try again or contact support.',
    });
    expect(response.status).toBe(502);
    expect(deleteServerAuthUser).not.toHaveBeenCalled();
    expect(supabase.calls).toEqual([
      'progress_photos.user_id=user_123',
      'daily_metrics.user_id=user_123',
      'body_metrics.user_id=user_123',
    ]);
  });

  it('deletes the Clerk user only after asset and row cleanup succeeds', async () => {
    const supabase = createMockSupabase();
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);

    const response = await DELETE();

    await expect(response.json()).resolves.toEqual({
      message: 'Account deleted successfully',
    });
    expect(response.status).toBe(200);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://supabase.example/functions/v1/delete-user-assets',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer clerk-token',
        }),
      }),
    );
    expect(supabase.calls).toEqual([
      'progress_photos.user_id=user_123',
      'daily_metrics.user_id=user_123',
      'body_metrics.user_id=user_123',
      'user_goals.user_id=user_123',
      'profiles.id=user_123',
    ]);
    expect(deleteServerAuthUser).toHaveBeenCalledWith('user_123');
  });

  it('keeps the Clerk user when asset cleanup fails', async () => {
    const supabase = createMockSupabase();
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: false,
      status: 500,
      text: async () => 'asset cleanup failed',
    });

    const response = await DELETE();

    expect(response.status).toBe(502);
    expect(supabase.calls).toEqual([]);
    expect(deleteServerAuthUser).not.toHaveBeenCalled();
  });

  it('fails closed when the asset cleanup function is not configured', async () => {
    const supabase = createMockSupabase();
    (createAuthenticatedDataClient as jest.Mock).mockResolvedValue(supabase.client);
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;

    const response = await DELETE();

    await expect(response.json()).resolves.toEqual({
      error: 'Unable to delete all account data. Please try again or contact support.',
    });
    expect(response.status).toBe(502);
    expect(global.fetch).not.toHaveBeenCalled();
    expect(supabase.calls).toEqual([]);
    expect(deleteServerAuthUser).not.toHaveBeenCalled();
  });
});
