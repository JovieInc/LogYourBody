/**
 * @jest-environment node
 */
import { DELETE } from '../route';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

jest.mock('@/lib/ports/server-auth-runtime', () => ({
  getServerAuthSession: jest.fn(),
}));

describe('DELETE /api/auth/delete-account', () => {
  const getToken = jest.fn();
  const originalFetch = global.fetch;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.example';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key';
    getToken.mockResolvedValue('product-token');
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: 'user_123', getToken });
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it('rejects an unauthenticated request', async () => {
    (getServerAuthSession as jest.Mock).mockResolvedValue({ userId: null, getToken });

    const response = await DELETE();

    expect(response.status).toBe(401);
  });

  it('delegates complete product deletion to the authenticated edge function', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('{}', { status: 200 }));

    const response = await DELETE();

    expect(response.status).toBe(200);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://supabase.example/functions/v1/delete-user-assets',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({ Authorization: 'Bearer product-token' }),
      }),
    );
  });

  it('fails closed when the edge function cannot complete deletion', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('{}', { status: 502 }));

    const response = await DELETE();

    expect(response.status).toBe(502);
  });
});
