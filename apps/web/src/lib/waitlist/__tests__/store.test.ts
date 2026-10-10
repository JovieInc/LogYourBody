import { acceptWaitlistEntry, summarizeWaitlistRegistrations } from '../store';

const mockQuery = jest.fn();

jest.mock('@neondatabase/serverless', () => ({
  neon: jest.fn(() => mockQuery),
}));

describe('acceptWaitlistEntry', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.WAITLIST_DATABASE_URL = 'postgresql://example.test/waitlist';
  });

  it('creates a normalized waitlist entry', async () => {
    mockQuery.mockResolvedValueOnce([{ created: true }]);

    await expect(
      acceptWaitlistEntry({ email: ' New@Example.com ', source: 'landing:minimal:direct' }),
    ).resolves.toEqual({ created: true });

    expect(mockQuery).toHaveBeenCalledTimes(1);
    expect(mockQuery.mock.calls[0]?.slice(1)).toEqual([
      'new@example.com',
      'new@example.com',
      'landing:minimal:direct',
    ]);
  });

  it('accepts repeat submissions idempotently', async () => {
    mockQuery.mockResolvedValueOnce([]);
    await expect(
      acceptWaitlistEntry({ email: 'existing@example.com', source: 'landing:minimal:direct' }),
    ).resolves.toEqual({ created: false });
    const statement = mockQuery.mock.calls[0][0].join('?');
    expect(statement).toContain('on conflict (email_normalized) do nothing');
    expect(statement).not.toContain('update');
  });

  it('throws on invalid email before hitting the database', async () => {
    await expect(
      acceptWaitlistEntry({ email: 'bad-email', source: 'landing:minimal:direct' }),
    ).rejects.toThrow('INVALID_EMAIL');
    expect(mockQuery).not.toHaveBeenCalled();
  });

  it('propagates a failed insert rather than issuing a registration receipt', async () => {
    mockQuery.mockRejectedValueOnce(new Error('unavailable'));
    await expect(
      acceptWaitlistEntry({ email: 'synthetic@example.com', source: 'landing:minimal:direct' }),
    ).rejects.toThrow('unavailable');
  });

  it('reports only bounded durable aggregate evidence with explicit unknown cohort qualification', async () => {
    mockQuery.mockResolvedValueOnce([{ count: '3', observed_at: '2026-10-06T12:00:00Z' }]);
    const report = await summarizeWaitlistRegistrations({
      from: '2026-10-01T00:00:00Z',
      to: '2026-10-06T00:00:00Z',
    });
    expect(report).toEqual({
      schema_version: 1,
      metric: 'unique_persisted_waitlist_registrations',
      environment: 'unclassified',
      window_start: '2026-10-01T00:00:00.000Z',
      window_end: '2026-10-06T00:00:00.000Z',
      observed_at: '2026-10-06T12:00:00.000Z',
      count: 3,
      qualified_real_users: null,
      exclusions_applied: [],
    });
    const statement = mockQuery.mock.calls[0][0].join('?').replace(/\s+/g, ' ');
    expect(statement).toContain('created_at >= ?::timestamptz');
    expect(statement).toContain('created_at < ?::timestamptz');
    expect(statement).not.toMatch(/email|source|status/);
    expect(mockQuery.mock.calls[0].slice(1)).toEqual([report.window_start, report.window_end]);
  });

  it.each([
    { from: 'invalid', to: '2026-10-06' },
    { from: '2026-10-06', to: '2026-10-01' },
    { from: '2026-10-06', to: '2026-10-06' },
  ])('rejects invalid report windows before querying', async (window) => {
    await expect(summarizeWaitlistRegistrations(window)).rejects.toThrow('INVALID_WAITLIST_WINDOW');
    expect(mockQuery).not.toHaveBeenCalled();
  });
});
