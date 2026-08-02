/**
 * @jest-environment node
 */
import { DELETE } from '../route';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { deleteUserHealthData } from '@/lib/supabase/account-deletion';

jest.mock('@/lib/ports/server-auth-runtime', () => ({
  getServerAuthSession: jest.fn(),
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { deleteUser: jest.fn() },
}));
jest.mock('@/lib/supabase/account-deletion', () => ({
  deleteUserHealthData: jest.fn(),
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

  it('deletes the authenticated product principal from Neon', async () => {
    const response = await DELETE();

    expect(response.status).toBe(200);
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledWith('user_123');
  });

  it('deletes health data before removing the product principal', async () => {
    const response = await DELETE();

    expect(response.status).toBe(200);
    expect(deleteUserHealthData).toHaveBeenCalledWith('user_123');
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledWith('user_123');
    expect(jest.mocked(deleteUserHealthData).mock.invocationCallOrder[0]).toBeLessThan(
      jest.mocked(neonUserDirectory.deleteUser).mock.invocationCallOrder[0],
    );
  });

  it('fails closed when Neon cannot complete deletion', async () => {
    jest.mocked(neonUserDirectory.deleteUser).mockRejectedValue(new Error('database unavailable'));

    const response = await DELETE();

    expect(response.status).toBe(500);
  });

  it('fails closed when health-data deletion cannot complete', async () => {
    jest.mocked(deleteUserHealthData).mockRejectedValue(new Error('database unavailable'));

    const response = await DELETE();

    expect(response.status).toBe(500);
    expect(neonUserDirectory.deleteUser).not.toHaveBeenCalled();
  });
});
