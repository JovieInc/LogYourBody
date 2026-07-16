/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { GET, PATCH } from '../route';

jest.mock('@/lib/auth/jovie-oauth', () => ({
  authCookies: { accessToken: 'lyb_access_token' },
  fetchUserInfo: jest.fn(),
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { getUser: jest.fn(), updateProfile: jest.fn() },
}));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);
const mockedDirectory = jest.mocked(neonUserDirectory);
const identity = { sub: 'jovie-user-1' };
const user = {
  subject: identity.sub,
  phoneNumber: null,
  email: 'user@example.com',
  displayName: 'Test User',
  avatarUrl: null,
  profileData: { height: 180, height_unit: 'cm' },
  onboardingCompletedAt: new Date('2026-07-14T20:00:00.000Z'),
  legalAcceptedAt: null,
  termsVersion: null,
  privacyVersion: null,
};

function request(method: string, body?: unknown) {
  return new NextRequest('http://localhost/api/profile', {
    method,
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
}

function authenticatedRequest(method: string, body?: unknown) {
  const result = request(method, body);
  result.cookies.set('lyb_access_token', 'access-token');
  return result;
}

describe('/api/profile', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects requests without the Jovie session cookie', async () => {
    await expect(GET(request('GET'))).resolves.toHaveProperty('status', 401);
    expect(mockedFetchUserInfo).not.toHaveBeenCalled();
  });

  it('reads the product profile from Neon for the authenticated subject', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    mockedDirectory.getUser.mockResolvedValue(user);

    const response = await GET(authenticatedRequest('GET'));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      profile: {
        id: identity.sub,
        email: 'user@example.com',
        height: 180,
        onboarding_completed: true,
      },
    });
    expect(mockedDirectory.getUser).toHaveBeenCalledWith(identity.sub);
  });

  it('validates and persists profile changes through the Neon directory port', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    mockedDirectory.updateProfile.mockResolvedValue({
      ...user,
      profileData: { full_name: 'Updated User' },
    });

    const response = await PATCH(
      authenticatedRequest('PATCH', { fullName: 'Updated User', height: 180, heightUnit: 'cm' }),
    );

    expect(response.status).toBe(200);
    expect(mockedDirectory.updateProfile).toHaveBeenCalledWith(identity.sub, {
      profileData: { full_name: 'Updated User', height: 180, height_unit: 'cm' },
      displayName: 'Updated User',
      onboardingCompleted: undefined,
    });
  });

  it('rejects invalid profile updates before touching Neon', async () => {
    mockedFetchUserInfo.mockResolvedValue(identity);
    const response = await PATCH(authenticatedRequest('PATCH', { height: 10 }));
    expect(response.status).toBe(400);
    expect(mockedDirectory.updateProfile).not.toHaveBeenCalled();
  });
});
