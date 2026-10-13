jest.mock('@neondatabase/serverless', () => ({
  neon: jest.fn(),
}));

import { neon } from '@neondatabase/serverless';
import { neonUserDirectory } from './user-directory-adapter';

const admission = { subject: 'jovie-subject', ownerId: '11111111-1111-4111-8111-111111111111' };
const mockQuery = jest.fn();
const mockTransaction = jest.fn();
const mockSql = Object.assign(jest.fn(), { transaction: mockTransaction, query: mockQuery });
const mockNeon = jest.mocked(neon);

function normalizedStatement(callIndex: number): string {
  const [strings] = mockSql.mock.calls[callIndex] as [TemplateStringsArray, ...unknown[]];
  return strings.join('?').replace(/\s+/g, ' ').trim();
}

describe('neonUserDirectory.deleteUser', () => {
  beforeEach(() => {
    mockSql.mockReset();
    mockSql.mockReturnValue({ query: true });
    mockQuery.mockReset();
    mockQuery.mockReturnValue({ guard: true });
    mockTransaction.mockReset();
    mockTransaction.mockResolvedValue([]);
    mockNeon.mockReturnValue(mockSql as unknown as ReturnType<typeof neon>);
    process.env.DATABASE_URL = 'postgresql://example.test/logyourbody';
  });

  it('deletes chat state and health rows before the identity projection', async () => {
    await neonUserDirectory.deleteUser(admission);

    expect(mockQuery).toHaveBeenCalledWith('select public.lyb_native_account_admit($1, $2::uuid)', [
      admission.subject,
      admission.ownerId,
    ]);
    const expected = [
      'delete from public.chat_usage_limits where user_subject = ?',
      'delete from public.chat_conversations where user_subject = ?',
      'delete from public.body_metrics where user_subject = ?',
      'delete from public.native_records where user_subject = ?',
      "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ?",
    ];
    expected.forEach((statement, index) => expect(normalizedStatement(index)).toBe(statement));
    mockSql.mock.calls.forEach((call) => expect(call[1]).toBe('jovie-subject'));
    expect(mockTransaction).toHaveBeenCalledWith([
      { guard: true },
      ...mockSql.mock.results.map((result) => result.value),
    ]);
  });

  it('keeps the identity projection when health-row deletion fails', async () => {
    mockTransaction.mockRejectedValueOnce(new Error('chat cleanup unavailable'));

    await expect(neonUserDirectory.deleteUser(admission)).rejects.toThrow(
      'chat cleanup unavailable',
    );

    expect(mockTransaction).toHaveBeenCalledTimes(1);
  });
});
