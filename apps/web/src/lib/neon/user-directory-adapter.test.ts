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

  it('deletes health rows before the identity projection', async () => {
    await neonUserDirectory.deleteUser('jovie-subject');

    expect(normalizedStatement(0)).toBe('delete from public.body_metrics where user_subject = ?');
    expect(mockSql.mock.calls[0]?.[1]).toBe('jovie-subject');
    expect(normalizedStatement(1)).toBe(
      "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ?",
    );
    expect(mockSql.mock.calls[1]?.[1]).toBe('jovie-subject');
  });

  it('keeps the identity projection when health-row deletion fails', async () => {
    mockSql.mockRejectedValueOnce(new Error('health deletion unavailable'));

    await expect(neonUserDirectory.deleteUser('jovie-subject')).rejects.toThrow(
      'health deletion unavailable',
    );

    expect(mockSql).toHaveBeenCalledTimes(1);
  });
});
