import { NextRequest, NextResponse } from 'next/server';
import {
  oauthClientId,
  oauthIssuer,
  oauthRedirectUri,
  pkceChallenge,
  randomBase64Url,
  safeReturnTo,
  setOAuthTransaction,
} from '@/lib/auth/jovie-oauth';

export async function GET(request: NextRequest) {
  const state = randomBase64Url();
  const verifier = randomBase64Url(48);
  const redirectUri = oauthRedirectUri(request);
  const authorize = new URL(`${oauthIssuer()}/oauth2/authorize`);
  authorize.searchParams.set('client_id', oauthClientId());
  authorize.searchParams.set('redirect_uri', redirectUri);
  authorize.searchParams.set('response_type', 'code');
  authorize.searchParams.set('scope', 'openid profile email offline_access');
  authorize.searchParams.set('state', state);
  authorize.searchParams.set('code_challenge', pkceChallenge(verifier));
  authorize.searchParams.set('code_challenge_method', 'S256');

  const response = NextResponse.redirect(authorize);
  setOAuthTransaction(response, {
    state,
    verifier,
    returnTo: safeReturnTo(request.nextUrl.searchParams.get('returnTo')),
  });
  return response;
}
