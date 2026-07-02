import { upsertWaitlistEntry } from '../store';

const mockMaybeSingle = jest.fn();
const mockSingle = jest.fn();
const mockInsert = jest.fn();
const mockSelect = jest.fn();
const mockEq = jest.fn();
const mockFrom = jest.fn();

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => ({
    from: mockFrom,
  })),
}));

describe('upsertWaitlistEntry', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-key';

    mockFrom.mockImplementation(() => ({
      select: mockSelect,
      insert: mockInsert,
    }));

    mockSelect.mockImplementation(() => ({
      eq: mockEq,
    }));

    mockEq.mockImplementation(() => ({
      maybeSingle: mockMaybeSingle,
    }));

    mockInsert.mockImplementation(() => ({
      select: mockSelect,
    }));
  });

  it('creates a new waitlist entry when email is new', async () => {
    mockMaybeSingle.mockResolvedValueOnce({ data: null, error: null });
    mockSingle.mockResolvedValueOnce({ data: { id: 'entry-1' }, error: null });
    mockSelect.mockImplementationOnce(() => ({
      eq: mockEq,
    }));
    mockSelect.mockImplementationOnce(() => ({
      single: mockSingle,
    }));

    const result = await upsertWaitlistEntry({ email: 'new@example.com' });

    expect(result).toEqual({ status: 'created', id: 'entry-1' });
    expect(mockInsert).toHaveBeenCalledWith({
      email: 'new@example.com',
      email_normalized: 'new@example.com',
      source: 'landing',
    });
  });

  it('returns existing entry without inserting duplicates', async () => {
    mockMaybeSingle.mockResolvedValueOnce({ data: { id: 'entry-2' }, error: null });

    const result = await upsertWaitlistEntry({ email: 'existing@example.com' });

    expect(result).toEqual({ status: 'existing', id: 'entry-2' });
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it('throws on invalid email before hitting the database', async () => {
    await expect(upsertWaitlistEntry({ email: 'bad-email' })).rejects.toThrow('INVALID_EMAIL');
    expect(mockFrom).not.toHaveBeenCalled();
  });
});
