import type { BodyMetrics, UserProfile } from '@/types/body-metrics';
import type { DailyMetrics } from '@/lib/db/indexed-db';

type UnsyncedItems = {
  bodyMetrics: BodyMetrics[];
  dailyMetrics: DailyMetrics[];
  profiles: UserProfile[];
};

type TableName = 'profiles' | 'body_metrics' | 'daily_metrics';

const emptyUnsynced: UnsyncedItems = {
  bodyMetrics: [],
  dailyMetrics: [],
  profiles: [],
};

const dailyId = '11111111-1111-4111-8111-111111111111';

function profile(overrides: Partial<UserProfile> = {}): UserProfile {
  return {
    id: 'user_1',
    email: 'test@example.com',
    email_verified: true,
    onboarding_completed: true,
    settings: {},
    created_at: '2026-06-20T12:00:00.000Z',
    updated_at: '2026-06-20T12:00:00.000Z',
    ...overrides,
  };
}

function bodyMetric(overrides: Partial<BodyMetrics> = {}): BodyMetrics {
  return {
    id: 'metric_1',
    user_id: 'user_1',
    date: '2026-06-20T12:00:00.000Z',
    weight: 180,
    weight_unit: 'lbs',
    created_at: '2026-06-20T12:00:00.000Z',
    updated_at: '2026-06-20T12:00:00.000Z',
    ...overrides,
  };
}

function dailyMetric(overrides: Partial<DailyMetrics> = {}): DailyMetrics {
  return {
    id: dailyId,
    user_id: 'user_1',
    date: new Date('2026-06-20T12:00:00.000Z'),
    steps: 8_000,
    created_at: new Date('2026-06-20T12:00:00.000Z'),
    updated_at: new Date('2026-06-20T12:00:00.000Z'),
    ...overrides,
  };
}

async function loadSyncManager({ online = true } = {}) {
  jest.resetModules();
  jest.useFakeTimers();

  Object.defineProperty(window.navigator, 'onLine', {
    configurable: true,
    value: online,
  });

  const indexedDBMock = {
    clearAllData: jest.fn().mockResolvedValue(undefined),
    getBodyMetrics: jest.fn().mockResolvedValue([]),
    getDailyMetrics: jest.fn().mockResolvedValue(null),
    getUnsyncedItems: jest.fn().mockResolvedValue(emptyUnsynced),
    markAsSynced: jest.fn().mockResolvedValue(undefined),
    saveBodyMetrics: jest.fn().mockResolvedValue(undefined),
    saveDailyMetrics: jest.fn().mockResolvedValue(undefined),
    updateSyncStatus: jest.fn().mockResolvedValue(undefined),
  };

  const upserts: Array<{ table: TableName; payload: Record<string, unknown> }> = [];
  const tableErrors = new Map<TableName, { message: string }>();
  const fetchUrls: string[] = [];

  const fetchMock = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    fetchUrls.push(url);
    const method = (init?.method || 'GET').toUpperCase();
    const payload = init?.body
      ? (JSON.parse(String(init.body)) as Record<string, unknown> | unknown[])
      : {};

    const jsonResponse = (body: unknown, status: number) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
      }) as Response;

    if (url.includes('/api/profile') && method === 'GET') {
      return jsonResponse({ profile: { id: 'user_1' } }, 200);
    }
    if (url.includes('/api/profile') && method === 'PATCH') {
      upserts.push({ table: 'profiles', payload: payload as Record<string, unknown> });
      if (tableErrors.has('profiles')) return jsonResponse({ error: 'fail' }, 500);
      return jsonResponse({ profile: { id: 'user_1' } }, 200);
    }
    if (url.includes('/api/body-metrics') && method === 'POST') {
      upserts.push({ table: 'body_metrics', payload: payload as Record<string, unknown> });
      if (tableErrors.has('body_metrics')) return jsonResponse({ error: 'fail' }, 500);
      return jsonResponse({ metric: {} }, 201);
    }
    if (url.includes('/daily-metrics') && method === 'POST') {
      const records = Array.isArray(payload) ? payload : [];
      upserts.push({
        table: 'daily_metrics',
        payload: (records[0] as Record<string, unknown>) || {},
      });
      if (tableErrors.has('daily_metrics')) return jsonResponse({ error: 'fail' }, 500);
      return jsonResponse({ records: [] }, 200);
    }
    return jsonResponse({ error: 'not found' }, 404);
  });

  jest.doMock('@/lib/db/indexed-db', () => ({ indexedDB: indexedDBMock }));
  global.fetch = fetchMock as typeof fetch;

  const module = await import('../sync-manager');
  await Promise.resolve();
  fetchMock.mockClear();
  fetchUrls.length = 0;

  return {
    fetchMock,
    fetchUrls,
    indexedDBMock,
    syncManager: module.syncManager,
    tableErrors,
    upserts,
  };
}

describe('syncManager', () => {
  let consoleErrorSpy: jest.SpyInstance;

  beforeEach(() => {
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(async () => {
    const { syncManager } = await import('../sync-manager');
    syncManager.destroy();
    consoleErrorSpy.mockRestore();
    jest.useRealTimers();
    jest.resetModules();
  });

  it('uploads unsynced profile, body metric, and daily metric records to first-party Neon APIs', async () => {
    const { indexedDBMock, syncManager, upserts } = await loadSyncManager();
    indexedDBMock.getUnsyncedItems
      .mockResolvedValueOnce({
        bodyMetrics: [bodyMetric()],
        dailyMetrics: [dailyMetric()],
        profiles: [profile()],
      })
      .mockResolvedValueOnce(emptyUnsynced);

    const states: Array<{ pendingSyncCount: number; syncStatus: string }> = [];
    const unsubscribe = syncManager.subscribe((state) => states.push(state));

    await syncManager.syncAll();

    expect(upserts).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          payload: expect.objectContaining({ onboardingCompleted: true }),
          table: 'profiles',
        }),
        expect.objectContaining({
          payload: expect.objectContaining({ date: '2026-06-20', weight: 180, weightUnit: 'lbs' }),
          table: 'body_metrics',
        }),
        expect.objectContaining({
          payload: expect.objectContaining({ id: dailyId, steps: 8_000, user_id: 'user_1' }),
          table: 'daily_metrics',
        }),
      ]),
    );
    expect(indexedDBMock.markAsSynced).toHaveBeenCalledWith('profiles', 'user_1');
    expect(indexedDBMock.markAsSynced).toHaveBeenCalledWith('bodyMetrics', 'metric_1');
    expect(indexedDBMock.markAsSynced).toHaveBeenCalledWith('dailyMetrics', dailyId);
    expect(indexedDBMock.updateSyncStatus).toHaveBeenCalledWith('profiles', 'user_1', 'synced');
    expect(indexedDBMock.updateSyncStatus).toHaveBeenCalledWith(
      'bodyMetrics',
      'metric_1',
      'synced',
    );
    expect(indexedDBMock.updateSyncStatus).toHaveBeenCalledWith('dailyMetrics', dailyId, 'synced');
    expect(states.at(-1)).toMatchObject({ pendingSyncCount: 0, syncStatus: 'success' });

    unsubscribe();
  });

  it('continues syncing other pending records and reports an error when one table upload fails', async () => {
    const { indexedDBMock, syncManager, tableErrors, upserts } = await loadSyncManager();
    tableErrors.set('body_metrics', { message: 'body metric upload failed' });
    indexedDBMock.getUnsyncedItems
      .mockResolvedValueOnce({
        bodyMetrics: [bodyMetric()],
        dailyMetrics: [dailyMetric()],
        profiles: [profile()],
      })
      .mockResolvedValueOnce({
        bodyMetrics: [bodyMetric()],
        dailyMetrics: [],
        profiles: [],
      });

    const states: Array<{ error?: string; pendingSyncCount: number; syncStatus: string }> = [];
    const unsubscribe = syncManager.subscribe((state) => states.push(state));

    await syncManager.syncAll();

    expect(upserts.map((entry) => entry.table)).toEqual([
      'profiles',
      'body_metrics',
      'daily_metrics',
    ]);
    expect(indexedDBMock.markAsSynced).toHaveBeenCalledWith('profiles', 'user_1');
    expect(indexedDBMock.markAsSynced).not.toHaveBeenCalledWith('bodyMetrics', 'metric_1');
    expect(indexedDBMock.markAsSynced).toHaveBeenCalledWith('dailyMetrics', dailyId);
    expect(states.at(-1)).toMatchObject({
      error: 'Some items failed to sync',
      pendingSyncCount: 1,
      syncStatus: 'error',
    });

    unsubscribe();
  });

  it('stores new weight entries locally without attempting immediate sync while offline', async () => {
    const { fetchMock, indexedDBMock, syncManager, upserts } = await loadSyncManager({
      online: false,
    });
    const randomUUIDSpy = jest.spyOn(crypto, 'randomUUID').mockReturnValue('metric_local');
    indexedDBMock.getUnsyncedItems.mockResolvedValue({
      bodyMetrics: [bodyMetric({ id: 'metric_local' })],
      dailyMetrics: [],
      profiles: [],
    });

    const saved = await syncManager.logWeight(181.5, 'lbs', 'morning weigh-in');

    expect(saved).toMatchObject({
      id: 'metric_local',
      notes: 'morning weigh-in',
      user_id: 'user_1',
      weight: 181.5,
      weight_unit: 'lbs',
    });
    expect(indexedDBMock.saveBodyMetrics).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 'metric_local',
        notes: 'morning weigh-in',
        user_id: 'user_1',
        weight: 181.5,
        weight_unit: 'lbs',
      }),
      'user_1',
    );
    expect(upserts).toEqual([]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(String(fetchMock.mock.calls[0]?.[0])).toContain('/api/profile');

    randomUUIDSpy.mockRestore();
  });

  it('clears local state on logout data cleanup', async () => {
    const { indexedDBMock, syncManager } = await loadSyncManager();
    const states: Array<{
      lastSyncDate: Date | null;
      pendingSyncCount: number;
      syncStatus: string;
    }> = [];
    const unsubscribe = syncManager.subscribe((state) => states.push(state));

    await syncManager.clearAllData();

    expect(indexedDBMock.clearAllData).toHaveBeenCalledTimes(1);
    expect(states.at(-1)).toMatchObject({
      lastSyncDate: null,
      pendingSyncCount: 0,
      syncStatus: 'idle',
    });

    unsubscribe();
  });
});
