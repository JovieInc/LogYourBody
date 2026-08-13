jest.mock('@neondatabase/serverless', () => ({
  neon: jest.fn(),
}));

import { neon } from '@neondatabase/serverless';
import { neonUserDirectory } from './user-directory-adapter';

const mockSql = jest.fn();
const mockNeon = jest.mocked(neon);

function normalizedStatement(callIndex: number): string {
  const [strings] = mockSql.mock.calls[callIndex] as [TemplateStringsArray, ...unknown[]];
  return strings.join('?').replace(/\s+/g, ' ').trim();
}

describe('neonUserDirectory.deleteUser', () => {
  beforeEach(() => {
    mockSql.mockReset();
    mockSql.mockResolvedValue([]);
    mockNeon.mockReturnValue(mockSql as unknown as ReturnType<typeof neon>);
    process.env.DATABASE_URL = 'postgresql://example.test/logyourbody';
  });

  it('deletes chat state and health rows before the identity projection', async () => {
    await neonUserDirectory.deleteUser('jovie-subject');

    expect(normalizedStatement(0)).toBe(
      'delete from public.chat_usage_limits where user_subject = ?',
    );
    expect(mockSql.mock.calls[0]?.[1]).toBe('jovie-subject');
    expect(normalizedStatement(1)).toBe(
      'delete from public.chat_conversations where user_subject = ?',
    );
    expect(mockSql.mock.calls[1]?.[1]).toBe('jovie-subject');
    expect(normalizedStatement(2)).toBe('delete from public.body_metrics where user_subject = ?');
    expect(mockSql.mock.calls[2]?.[1]).toBe('jovie-subject');
    expect(normalizedStatement(3)).toBe('delete from public.native_records where user_subject = ?');
    expect(mockSql.mock.calls[3]?.[1]).toBe('jovie-subject');
    expect(normalizedStatement(4)).toBe(
      "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ?",
    );
    expect(mockSql.mock.calls[4]?.[1]).toBe('jovie-subject');
  });

  it('keeps the identity projection when health-row deletion fails', async () => {
    mockSql.mockRejectedValueOnce(new Error('chat cleanup unavailable'));

    await expect(neonUserDirectory.deleteUser('jovie-subject')).rejects.toThrow(
      'chat cleanup unavailable',
    );

    expect(mockSql).toHaveBeenCalledTimes(1);
  });
});
