/** @jest-environment node */

import { deleteUserHealthData } from './account-deletion';

jest.mock('server-only', () => ({}));

const originalEnvironment = process.env;

describe('deleteUserHealthData', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env = {
      ...originalEnvironment,
      NEXT_PUBLIC_SUPABASE_URL: 'https://project.supabase.co/',
      SUPABASE_SERVICE_ROLE_KEY: 'server-service-key',
    };
  });

  afterAll(() => {
    process.env = originalEnvironment;
  });

  it('uses the server credential to delete data for the exact authenticated subject', async () => {
    global.fetch = jest.fn(async () => new Response('{}', { status: 200 }));

    await deleteUserHealthData('jovie-user-1');

    expect(global.fetch).toHaveBeenCalledWith(
      'https://project.supabase.co/functions/v1/delete-user-assets',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          authorization: 'Bearer server-service-key',
          apikey: 'server-service-key',
        }),
        body: JSON.stringify({ userId: 'jovie-user-1' }),
        cache: 'no-store',
      }),
    );
  });

  it('fails closed when the asset-deletion function does not confirm success', async () => {
    global.fetch = jest.fn(async () => new Response('{}', { status: 503 }));

    await expect(deleteUserHealthData('jovie-user-1')).rejects.toThrow(
      'Account data deletion failed with status 503',
    );
  });
});
