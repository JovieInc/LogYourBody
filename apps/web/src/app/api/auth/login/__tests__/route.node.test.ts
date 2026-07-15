/** @jest-environment node */

import { NextRequest } from 'next/server';
import { GET } from '../route';

describe('GET /api/auth/login', () => {
  it('starts a direct Jovie authorization-code flow with PKCE and state', async () => {
    const response = await GET(
      new NextRequest('http://localhost:3000/api/auth/login?returnTo=%2Fdashboard'),
    );
    const location = new URL(response.headers.get('location') || '');

    expect(location.origin + location.pathname).toBe('https://jov.ie/api/auth/oauth2/authorize');
    expect(location.searchParams.get('client_id')).toBe('logyourbody-web');
    expect(location.searchParams.get('redirect_uri')).toBe(
      'http://localhost:3000/api/auth/callback',
    );
    expect(location.searchParams.get('response_type')).toBe('code');
    expect(location.searchParams.get('scope')).toBe('openid profile email phone offline_access');
    expect(location.searchParams.get('code_challenge_method')).toBe('S256');
    expect(location.searchParams.get('code_challenge')).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(response.cookies.get('lyb_oauth_state')?.value).toBe(location.searchParams.get('state'));
    expect(response.cookies.get('lyb_oauth_verifier')?.value).toBeTruthy();
    expect(response.cookies.get('lyb_oauth_return_to')?.value).toBe('/dashboard');
  });

  it('does not accept an external return URL', async () => {
    const response = await GET(
      new NextRequest('http://localhost:3000/api/auth/login?returnTo=https%3A%2F%2Fevil.example'),
    );

    expect(response.cookies.get('lyb_oauth_return_to')?.value).toBe('/onboarding');
  });
});
