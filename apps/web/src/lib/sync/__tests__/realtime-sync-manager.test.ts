type SyncStateSnapshot = {
  error?: string;
  pendingSyncCount: number;
  syncStatus: string;
};

type QueuedMutation = {
  column?: string;
  operation: 'INSERT' | 'UPDATE' | 'DELETE';
  payload?: Record<string, unknown>;
  table: string;
  value?: unknown;
};

const emptyUnsynced = {
  bodyMetrics: [],
  dailyMetrics: [],
  profiles: [],
};

async function flushQueuedTimers() {
  await jest.advanceTimersByTimeAsync(500);
  await jest.advanceTimersByTimeAsync(2_000);
  await Promise.resolve();
}

async function loadRealtimeSyncManager({
  mutationError = null,
}: {
  mutationError?: { message: string } | null;
} = {}) {
  jest.resetModules();
  jest.useFakeTimers();
  localStorage.clear();

  Object.defineProperty(window.navigator, 'onLine', {
    configurable: true,
    value: true,
  });

  const indexedDBMock = {
    getBodyMetrics: jest.fn().mockResolvedValue([]),
    getProfile: jest.fn().mockResolvedValue(null),
    getUnsyncedItems: jest.fn().mockResolvedValue(emptyUnsynced),
    saveBodyMetrics: jest.fn().mockResolvedValue(undefined),
    saveDailyMetrics: jest.fn().mockResolvedValue(undefined),
    saveProfile: jest.fn().mockResolvedValue(undefined),
  };

  const mutations: QueuedMutation[] = [];
  const mutationResult = () => Promise.resolve({ error: mutationError });

  const supabase = {
    channel: jest.fn(() => {
      const channel = {
        on: jest.fn(() => channel),
        subscribe: jest.fn(() => channel),
      };
      return channel;
    }),
    from: jest.fn((table: string) => ({
      delete: jest.fn(() => ({
        eq: jest.fn(async (column: string, value: unknown) => {
          mutations.push({ column, operation: 'DELETE', table, value });
          return mutationResult();
        }),
      })),
      insert: jest.fn(async (payload: Record<string, unknown>) => {
        mutations.push({ operation: 'INSERT', payload, table });
        return mutationResult();
      }),
      update: jest.fn((payload: Record<string, unknown>) => ({
        eq: jest.fn(async (column: string, value: unknown) => {
          mutations.push({ column, operation: 'UPDATE', payload, table, value });
          return mutationResult();
        }),
      })),
    })),
    removeChannel: jest.fn().mockResolvedValue(undefined),
  };

  jest.doMock('@/lib/db/indexed-db', () => ({ indexedDB: indexedDBMock }));
  jest.doMock('@/lib/supabase/client', () => ({ createClient: jest.fn(() => supabase) }));

  const module = await import('../realtime-sync-manager');
  await Promise.resolve();
  jest.clearAllMocks();

  return {
    indexedDBMock,
    mutations,
    realtimeSyncManager: module.realtimeSyncManager,
    supabase,
  };
}

describe('realtimeSyncManager queue processing', () => {
  let consoleErrorSpy: jest.SpyInstance;
  let randomUUIDSpy: jest.SpyInstance;

  beforeEach(() => {
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    randomUUIDSpy = jest.spyOn(crypto, 'randomUUID').mockReturnValue('queue_1');
  });

  afterEach(async () => {
    const { realtimeSyncManager } = await import('../realtime-sync-manager');
    realtimeSyncManager.destroy();
    consoleErrorSpy.mockRestore();
    randomUUIDSpy.mockRestore();
    localStorage.clear();
    jest.useRealTimers();
    jest.resetModules();
  });

  it('keeps a queued insert in storage and reports an error when Supabase returns an error payload', async () => {
    const { mutations, realtimeSyncManager } = await loadRealtimeSyncManager({
      mutationError: { message: 'network write failed' },
    });
    const states: SyncStateSnapshot[] = [];
    const unsubscribe = realtimeSyncManager.subscribe((state) => states.push(state));

    await realtimeSyncManager.queueChange({
      data: { id: 'metric_1', user_id: 'user_1', weight: 180 },
      operation: 'INSERT',
      table: 'body_metrics',
    });
    await flushQueuedTimers();

    expect(mutations).toEqual([
      expect.objectContaining({
        operation: 'INSERT',
        payload: expect.objectContaining({
          id: 'metric_1',
          sync_id: expect.stringMatching(/^client-/),
          user_id: 'user_1',
        }),
        table: 'body_metrics',
      }),
    ]);
    expect(JSON.parse(localStorage.getItem('syncQueue') ?? '[]')).toEqual([
      expect.objectContaining({
        id: 'queue_1',
        retryCount: 1,
        table: 'body_metrics',
      }),
    ]);
    expect(states.at(-1)).toMatchObject({
      error: 'network write failed',
      pendingSyncCount: 1,
      syncStatus: 'error',
    });

    unsubscribe();
  });

  it('removes a queued update from storage after Supabase accepts the mutation', async () => {
    const { mutations, realtimeSyncManager } = await loadRealtimeSyncManager();
    const states: SyncStateSnapshot[] = [];
    const unsubscribe = realtimeSyncManager.subscribe((state) => states.push(state));

    await realtimeSyncManager.queueChange({
      data: { body_fat_percentage: 15.5, id: 'metric_1', user_id: 'user_1' },
      operation: 'UPDATE',
      table: 'body_metrics',
    });
    await flushQueuedTimers();

    expect(mutations).toEqual([
      expect.objectContaining({
        column: 'id',
        operation: 'UPDATE',
        payload: expect.objectContaining({
          body_fat_percentage: 15.5,
          sync_id: expect.stringMatching(/^client-/),
        }),
        table: 'body_metrics',
        value: 'metric_1',
      }),
    ]);
    expect(JSON.parse(localStorage.getItem('syncQueue') ?? '[]')).toEqual([]);
    expect(states.at(-1)).toMatchObject({
      pendingSyncCount: 0,
      syncStatus: 'success',
    });

    unsubscribe();
  });
});
