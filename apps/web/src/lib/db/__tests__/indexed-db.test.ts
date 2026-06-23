import type { DailyMetrics } from '../indexed-db';

function dailyMetric(overrides: Partial<DailyMetrics> = {}): DailyMetrics {
  return {
    id: 'daily_1',
    user_id: 'user_123',
    date: new Date('2026-06-23T12:00:00.000Z'),
    steps: 8400,
    created_at: new Date('2026-06-23T12:00:00.000Z'),
    updated_at: new Date('2026-06-23T12:00:00.000Z'),
    ...overrides,
  };
}

function createDbMock() {
  const put = jest.fn();
  const getAll = jest.fn();
  const done = Promise.resolve();
  const index = jest.fn(() => ({ getAll }));
  const objectStore = jest.fn(() => ({
    put,
    index,
  }));
  const transaction = jest.fn(() => ({
    done,
    objectStore,
  }));

  return {
    done,
    getAll,
    index,
    objectStore,
    put,
    transaction,
  };
}

describe('IndexedDBManager daily metrics', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
  });

  async function loadIndexedDBWith(db: ReturnType<typeof createDbMock>) {
    jest.doMock('idb', () => ({
      openDB: jest.fn().mockResolvedValue(db),
    }));

    const module = await import('../indexed-db');
    return module.indexedDB;
  }

  it('normalizes daily metric date keys before saving to IndexedDB', async () => {
    const db = createDbMock();
    const localIndexedDB = await loadIndexedDBWith(db);

    await localIndexedDB.saveDailyMetrics(
      dailyMetric({
        created_at: '2026-06-23T11:00:00.000Z' as unknown as Date,
        date: '2026-06-23T10:00:00.000Z' as unknown as Date,
        updated_at: '2026-06-23T12:00:00.000Z' as unknown as Date,
      }),
    );

    expect(db.transaction).toHaveBeenCalledWith('dailyMetrics', 'readwrite');
    expect(db.put).toHaveBeenCalledWith(
      expect.objectContaining({
        created_at: new Date('2026-06-23T11:00:00.000Z'),
        date: new Date('2026-06-23T10:00:00.000Z'),
        sync_status: 'pending',
        updated_at: new Date('2026-06-23T12:00:00.000Z'),
      }),
    );
  });

  it('normalizes Supabase SQL date strings as local-day keys', async () => {
    const db = createDbMock();
    const localIndexedDB = await loadIndexedDBWith(db);
    const expectedLocalDate = new Date(2026, 5, 23);

    await localIndexedDB.saveDailyMetrics(
      dailyMetric({
        date: '2026-06-23' as unknown as Date,
      }),
    );

    expect(db.put).toHaveBeenCalledWith(
      expect.objectContaining({
        date: expectedLocalDate,
      }),
    );
  });

  it('queries daily metrics by the compound user and day key range', async () => {
    const db = createDbMock();
    const hiddenDeletedMetric = dailyMetric({ id: 'deleted', is_deleted: true });
    const visibleMetric = dailyMetric({ id: 'visible', steps: 9100 });
    db.getAll.mockResolvedValue([hiddenDeletedMetric, visibleMetric]);
    const localIndexedDB = await loadIndexedDBWith(db);
    const bound = jest.spyOn(IDBKeyRange, 'bound');

    const result = await localIndexedDB.getDailyMetrics(
      'user_123',
      new Date('2026-06-23T18:45:00.000Z'),
    );

    expect(db.transaction).toHaveBeenCalledWith('dailyMetrics', 'readonly');
    expect(db.index).toHaveBeenCalledWith('user_date');
    const expectedStart = new Date('2026-06-23T18:45:00.000Z');
    expectedStart.setHours(0, 0, 0, 0);
    const expectedEnd = new Date('2026-06-23T18:45:00.000Z');
    expectedEnd.setHours(23, 59, 59, 999);
    expect(bound).toHaveBeenCalledWith(['user_123', expectedStart], ['user_123', expectedEnd]);
    expect(db.getAll).toHaveBeenCalledWith(bound.mock.results[0]?.value);
    expect(result).toEqual(visibleMetric);
  });

  it('falls back to legacy string-keyed daily metrics and repairs them', async () => {
    const db = createDbMock();
    const localIndexedDB = await loadIndexedDBWith(db);
    const legacyMetric = dailyMetric({
      created_at: '2026-06-23T11:00:00.000Z' as unknown as Date,
      date: '2026-06-23' as unknown as Date,
      updated_at: '2026-06-23T12:00:00.000Z' as unknown as Date,
    });
    db.getAll.mockResolvedValueOnce([]).mockResolvedValueOnce([legacyMetric]);

    const result = await localIndexedDB.getDailyMetrics(
      'user_123',
      new Date('2026-06-23T18:45:00.000Z'),
    );

    expect(db.index).toHaveBeenNthCalledWith(1, 'user_date');
    expect(db.index).toHaveBeenNthCalledWith(2, 'user_id');
    expect(db.getAll).toHaveBeenNthCalledWith(2, 'user_123');
    expect(db.put).toHaveBeenCalledWith(
      expect.objectContaining({
        created_at: new Date('2026-06-23T11:00:00.000Z'),
        date: new Date(2026, 5, 23),
        updated_at: new Date('2026-06-23T12:00:00.000Z'),
      }),
    );
    expect(result).toEqual(
      expect.objectContaining({
        date: new Date(2026, 5, 23),
      }),
    );
  });

  it('returns null when the day match is deleted or outside the requested day', async () => {
    const db = createDbMock();
    db.getAll.mockResolvedValue([
      dailyMetric({ id: 'deleted', is_deleted: true }),
      dailyMetric({ id: 'next_day', date: new Date('2026-06-24T12:00:00.000Z') }),
    ]);
    const localIndexedDB = await loadIndexedDBWith(db);

    const result = await localIndexedDB.getDailyMetrics(
      'user_123',
      new Date('2026-06-23T12:00:00.000Z'),
    );

    expect(result).toBeNull();
  });
});
