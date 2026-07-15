import { acceptWaitlistEntry } from '../store';

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
    mockQuery.mockResolvedValueOnce([]);

    await acceptWaitlistEntry({ email: ' New@Example.com ', source: 'landing:minimal:direct' });

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
    ).resolves.toBeUndefined();
  });

  it('throws on invalid email before hitting the database', async () => {
    await expect(
      acceptWaitlistEntry({ email: 'bad-email', source: 'landing:minimal:direct' }),
    ).rejects.toThrow('INVALID_EMAIL');
    expect(mockQuery).not.toHaveBeenCalled();
  });
});
