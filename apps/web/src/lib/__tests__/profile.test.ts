import { getProfile, updateProfile } from '@/lib/profile';

describe('Neon-backed profile client contract', () => {
  const fetchMock = jest.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    global.fetch = fetchMock;
  });

  function response(body: unknown, status: number) {
    return { ok: status >= 200 && status < 300, status, json: async () => body };
  }

  it('maps the canonical API profile response', async () => {
    fetchMock.mockResolvedValue(
      response(
        {
          profile: {
            id: 'jovie-user-1',
            email: 'user@example.com',
            full_name: 'Test User',
            height: 180,
            height_unit: 'cm',
            onboarding_completed: true,
          },
        },
        200,
      ),
    );

    await expect(getProfile('jovie-user-1')).resolves.toMatchObject({
      id: 'jovie-user-1',
      email: 'user@example.com',
      full_name: 'Test User',
      height: 180,
      height_unit: 'cm',
      onboarding_completed: true,
      settings: {},
    });
    expect(fetchMock).toHaveBeenCalledWith('/api/profile', { cache: 'no-store' });
  });

  it('returns null for a missing Neon profile', async () => {
    fetchMock.mockResolvedValue(response({ error: 'Profile not found' }, 404));
    await expect(getProfile('missing-user')).resolves.toBeNull();
  });

  it('sends only supported profile fields when updating', async () => {
    fetchMock.mockResolvedValue(
      response({ profile: { id: 'jovie-user-1', onboarding_completed: true } }, 200),
    );

    await updateProfile('jovie-user-1', {
      id: 'jovie-user-1',
      full_name: 'Updated User',
      height: 180,
      height_unit: 'ft',
      created_at: 'legacy',
      updated_at: 'legacy',
      settings: { units: { weight: 'lbs' } },
    });

    expect(fetchMock).toHaveBeenCalledWith('/api/profile', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      cache: 'no-store',
      body: JSON.stringify({
        fullName: 'Updated User',
        dateOfBirth: undefined,
        height: 180,
        heightUnit: 'in',
        gender: undefined,
        activityLevel: undefined,
        goalWeight: undefined,
        goalWeightUnit: undefined,
        onboardingCompleted: undefined,
      }),
    });
  });

  it('surfaces API failures to the caller', async () => {
    fetchMock.mockResolvedValue(response({ error: 'failed' }, 500));
    await expect(updateProfile('jovie-user-1', { full_name: 'Test' })).rejects.toThrow(
      'Unable to load profile',
    );
  });
});
