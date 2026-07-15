import 'server-only';

import { createHash, randomBytes } from 'node:crypto';
import type { NextRequest, NextResponse } from 'next/server';
import { authCookies, type JovieUserInfo } from '@/lib/auth/constants';

export { authCookies } from '@/lib/auth/constants';
export type { JovieUserInfo } from '@/lib/auth/constants';

const DEFAULT_ISSUER = 'https://jov.ie/api/auth';
const DEFAULT_CLIENT_ID = 'logyourbody-web';

export type JovieTokenSet = {
  access_token: string;
  token_type: string;
  expires_in?: number;
  refresh_token?: string;
  id_token?: string;
  scope?: string;
};

export function oauthIssuer() {
  return (process.env.JOVIE_AUTH_ISSUER || DEFAULT_ISSUER).replace(/\/$/, '');
}

export function oauthClientId() {
  return process.env.JOVIE_AUTH_CLIENT_ID || DEFAULT_CLIENT_ID;
}

export function oauthRedirectUri(request?: NextRequest) {
  if (process.env.JOVIE_AUTH_REDIRECT_URI) return process.env.JOVIE_AUTH_REDIRECT_URI;
  if (process.env.NODE_ENV === 'production') {
    return 'https://logyourbody.com/api/auth/callback';
  }
  return `${request?.nextUrl.origin || 'http://localhost:3000'}/api/auth/callback`;
}

export function randomBase64Url(bytes = 32) {
  return randomBytes(bytes).toString('base64url');
}

export function pkceChallenge(verifier: string) {
  return createHash('sha256').update(verifier).digest('base64url');
}

export function safeReturnTo(value: string | null | undefined) {
  if (!value || !value.startsWith('/') || value.startsWith('//')) return '/onboarding';
  return value;
}

async function parseOAuthResponse(response: Response): Promise<JovieTokenSet> {
  const payload = (await response.json().catch(() => null)) as
    | (Partial<JovieTokenSet> & { error?: string; error_description?: string })
    | null;
  if (!response.ok || !payload?.access_token || !payload.token_type) {
    throw new Error(payload?.error_description || payload?.error || 'OAuth token exchange failed');
  }
  return payload as JovieTokenSet;
}

export async function exchangeAuthorizationCode(input: {
  code: string;
  verifier: string;
  redirectUri: string;
}) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: oauthClientId(),
    code: input.code,
    code_verifier: input.verifier,
    redirect_uri: input.redirectUri,
  });
  const response = await fetch(`${oauthIssuer()}/oauth2/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
    cache: 'no-store',
  });
  return parseOAuthResponse(response);
}

export async function refreshAccessToken(refreshToken: string) {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: oauthClientId(),
    refresh_token: refreshToken,
  });
  const response = await fetch(`${oauthIssuer()}/oauth2/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
    cache: 'no-store',
  });
  return parseOAuthResponse(response);
}

export async function fetchUserInfo(accessToken: string) {
  const response = await fetch(`${oauthIssuer()}/oauth2/userinfo`, {
    headers: { authorization: `Bearer ${accessToken}` },
    cache: 'no-store',
  });
  if (!response.ok) return null;
  const user = (await response.json()) as JovieUserInfo;
  return typeof user.sub === 'string' && user.sub ? user : null;
}

const secureCookie = process.env.NODE_ENV === 'production';
const cookieBase = { httpOnly: true, sameSite: 'lax' as const, secure: secureCookie, path: '/' };

export function setOAuthTransaction(
  response: NextResponse,
  input: { state: string; verifier: string; returnTo: string },
) {
  const options = { ...cookieBase, maxAge: 10 * 60 };
  response.cookies.set(authCookies.state, input.state, options);
  response.cookies.set(authCookies.verifier, input.verifier, options);
  response.cookies.set(authCookies.returnTo, input.returnTo, options);
}

export function setTokenCookies(response: NextResponse, tokens: JovieTokenSet) {
  response.cookies.set(authCookies.accessToken, tokens.access_token, {
    ...cookieBase,
    maxAge: tokens.expires_in || 15 * 60,
  });
  if (tokens.refresh_token) {
    response.cookies.set(authCookies.refreshToken, tokens.refresh_token, {
      ...cookieBase,
      maxAge: 60 * 60 * 24 * 30,
    });
  }
  if (tokens.id_token) {
    response.cookies.set(authCookies.idToken, tokens.id_token, {
      ...cookieBase,
      maxAge: 60 * 60 * 24 * 30,
    });
  }
}

export function clearOAuthTransaction(response: NextResponse) {
  for (const name of [authCookies.state, authCookies.verifier, authCookies.returnTo]) {
    response.cookies.set(name, '', { ...cookieBase, maxAge: 0 });
  }
}

export function clearTokenCookies(response: NextResponse) {
  for (const name of [authCookies.accessToken, authCookies.refreshToken, authCookies.idToken]) {
    response.cookies.set(name, '', { ...cookieBase, maxAge: 0 });
  }
}
