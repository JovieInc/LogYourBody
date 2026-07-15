/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { DELETE, GET, PATCH } from '../route';

jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: {
    getUser: jest.fn(),
    updateProfile: jest.fn(),
    deleteUser: jest.fn(),
  },
}));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);
const mockedDirectory = jest.mocked(neonUserDirectory);

const identity = { sub: 'jovie-user-1', phone_number: '+15551112222' };
const user = {
  subject: identity.sub,
  phoneNumber: identity.phone_number,
  email: null,
  displayName: 'Mobile User',
  avatarUrl: null,
  profileData: { height: 180, height_unit: 'cm' },
  onboardingCompletedAt: new Date('2026-07-14T20:00:00.000Z'),
  legalAcceptedAt: null,
  termsVersion: null,
  privacyVersion: null,
};

function request(method: string, body?: unknown) {
  return new NextRequest('http://localhost/api/auth/mobile/profile', {
    method,
    headers: {
      authorization: 'Bearer access-token',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

describe('/api/auth/mobile/profile', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects missing bearer authentication', async () => {
    const response = await GET(new NextRequest('http://localhost/api/auth/mobile/profile'));
    expect(response.status).toBe(401);
  });

  it('returns the Neon-backed product profile', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    mockedDirectory.getUser.mockResolvedValue(user);

    const response = await GET(request('GET'));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      profile: {
        id: identity.sub,
        height: 180,
        height_unit: 'cm',
        onboarding_completed: true,
      },
    });
  });

  it('validates and maps onboarding updates before persistence', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    mockedDirectory.updateProfile.mockResolvedValue({
      ...user,
      profileData: {
        full_name: 'Mobile User',
        date_of_birth: '1990-01-01',
        height: 180,
        height_unit: 'cm',
        gender: 'male',
        onboarding_completed: true,
      },
    });

    const response = await PATCH(
      request('PATCH', {
        fullName: 'Mobile User',
        dateOfBirth: '1990-01-01',
        height: 180,
        heightUnit: 'cm',
        gender: 'male',
        onboardingCompleted: true,
        legalAccepted: true,
      }),
    );

    expect(response.status).toBe(200);
    expect(mockedDirectory.updateProfile).toHaveBeenCalledWith(identity.sub, {
      profileData: {
        full_name: 'Mobile User',
        date_of_birth: '1990-01-01',
        height: 180,
        height_unit: 'cm',
        gender: 'male',
        onboarding_completed: true,
      },
      displayName: 'Mobile User',
      onboardingCompleted: true,
      acceptLegal: true,
      termsVersion: '2026-07-14',
      privacyVersion: '2026-07-14',
    });
  });

  it('deletes only the LYB product principal', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    const response = await DELETE(request('DELETE'));
    expect(response.status).toBe(204);
    expect(mockedDirectory.deleteUser).toHaveBeenCalledWith(identity.sub);
  });
});
