/**
 * @jest-environment node
 */
import { DELETE } from '../route';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

jest.mock('@/lib/ports/server-auth-runtime', () => ({
  getServerAuthSession: jest.fn(),
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { deleteUser: jest.fn() },
}));

describe('DELETE /api/auth/delete-account', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (getServerAuthSession as jest.Mock).mockResolvedValue({
      userId: 'user_123',
      getToken: async () => 'web-access-token',
    });
  });

  it('rejects an unauthenticated request', async () => {
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: null });

    const response = await DELETE();

    expect(response.status).toBe(401);
  });

  it('erases the authenticated product principal from Neon only', async () => {
    const response = await DELETE();

    expect(response.status).toBe(200);
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledWith('user_123');
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledTimes(1);
  });

  it('fails closed when Neon cannot complete deletion', async () => {
    jest.mocked(neonUserDirectory.deleteUser).mockRejectedValue(new Error('database unavailable'));

    const response = await DELETE();

    expect(response.status).toBe(500);
  });
});
