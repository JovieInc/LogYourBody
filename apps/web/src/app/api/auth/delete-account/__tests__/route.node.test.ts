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
  neonUserDirectory: { captureAccountAdmission: jest.fn(), deleteUser: jest.fn() },
}));

describe('DELETE /api/auth/delete-account', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest
      .mocked(neonUserDirectory.captureAccountAdmission)
      .mockResolvedValue({ subject: 'user_123', ownerId: '11111111-1111-4111-8111-111111111111' });
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
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledWith({
      subject: 'user_123',
      ownerId: '11111111-1111-4111-8111-111111111111',
    });
    expect(neonUserDirectory.deleteUser).toHaveBeenCalledTimes(1);
  });

  it('fails closed when Neon cannot complete deletion', async () => {
    jest.mocked(neonUserDirectory.deleteUser).mockRejectedValue(new Error('database unavailable'));

    const response = await DELETE();

    expect(response.status).toBe(500);
  });
});
