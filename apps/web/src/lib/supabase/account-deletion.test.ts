/** @jest-environment node */

import { deleteUserHealthData } from './account-deletion';

jest.mock('server-only', () => ({}));

describe('deleteUserHealthData', () => {
  it('fails closed instead of calling the retired Supabase function', async () => {
    global.fetch = jest.fn();

    await expect(deleteUserHealthData('jovie-user-1')).rejects.toThrow(
      'Supabase account-deletion service retired',
    );
    expect(global.fetch).not.toHaveBeenCalled();
  });
});
