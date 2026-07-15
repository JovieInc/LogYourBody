import { acceptWaitlistEntry } from '../store';

const mockInsert = jest.fn();
const mockFrom = jest.fn(() => ({ insert: mockInsert }));

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => ({ from: mockFrom })),
}));

describe('acceptWaitlistEntry', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-key';
  });

  it('creates a normalized waitlist entry', async () => {
    mockInsert.mockResolvedValueOnce({ error: null });

    await acceptWaitlistEntry({ email: ' New@Example.com ', source: 'landing:minimal:direct' });

    expect(mockInsert).toHaveBeenCalledWith({
      email: 'new@example.com',
      email_normalized: 'new@example.com',
      source: 'landing:minimal:direct',
    });
  });

  it('treats a uniqueness conflict as accepted', async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: '23505' } });
    await expect(
      acceptWaitlistEntry({ email: 'existing@example.com', source: 'landing:minimal:direct' }),
    ).resolves.toBeUndefined();
  });

  it('throws on invalid email before hitting the database', async () => {
    await expect(
      acceptWaitlistEntry({ email: 'bad-email', source: 'landing:minimal:direct' }),
    ).rejects.toThrow('INVALID_EMAIL');
    expect(mockFrom).not.toHaveBeenCalled();
  });
});
