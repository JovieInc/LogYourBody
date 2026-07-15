/** @jest-environment node */

import { NextRequest } from 'next/server';
import { GET } from '../route';

describe('GET /api/auth/callback', () => {
  it('rejects a callback whose state does not match the HttpOnly transaction cookie', async () => {
    const request = new NextRequest(
      'http://localhost:3000/api/auth/callback?code=test-code&state=attacker-state',
      { headers: { cookie: 'lyb_oauth_state=expected; lyb_oauth_verifier=verifier' } },
    );
    const response = await GET(request);

    expect(response.status).toBe(307);
    expect(response.headers.get('location')).toBe(
      'http://localhost:3000/signin?error=oauth_callback',
    );
    expect(response.cookies.get('lyb_oauth_state')?.value).toBe('');
    expect(response.cookies.get('lyb_oauth_verifier')?.value).toBe('');
  });
});
