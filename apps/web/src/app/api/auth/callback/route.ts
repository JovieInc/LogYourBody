import { NextRequest, NextResponse } from 'next/server';
import {
  authCookies,
  clearOAuthTransaction,
  exchangeAuthorizationCode,
  fetchUserInfo,
  oauthRedirectUri,
  safeReturnTo,
  setTokenCookies,
} from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get('code');
  const state = request.nextUrl.searchParams.get('state');
  const expectedState = request.cookies.get(authCookies.state)?.value;
  const verifier = request.cookies.get(authCookies.verifier)?.value;
  const returnTo = safeReturnTo(request.cookies.get(authCookies.returnTo)?.value);
  const redirectUri = oauthRedirectUri(request);
  const appOrigin = new URL(redirectUri).origin;
  const destination = new URL(returnTo, appOrigin);

  if (!code || !state || !expectedState || state !== expectedState || !verifier) {
    const response = NextResponse.redirect(new URL('/signin?error=oauth_callback', appOrigin));
    clearOAuthTransaction(response);
    return response;
  }

  try {
    const tokens = await exchangeAuthorizationCode({
      code,
      verifier,
      redirectUri,
    });
    const user = await fetchUserInfo(tokens.access_token);
    if (!user) throw new Error('Jovie did not return a valid user');
    await neonUserDirectory.recordSignIn({
      subject: user.sub,
      phoneNumber: user.phone_number,
      email: user.email,
      displayName: user.name,
      avatarUrl: user.picture,
    });
    const response = NextResponse.redirect(destination);
    setTokenCookies(response, tokens);
    clearOAuthTransaction(response);
    return response;
  } catch {
    const response = NextResponse.redirect(new URL('/signin?error=oauth_exchange', appOrigin));
    clearOAuthTransaction(response);
    return response;
  }
}
