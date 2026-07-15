import { NextRequest, NextResponse } from 'next/server';
import {
  authCookies,
  clearTokenCookies,
  fetchUserInfo,
  refreshAccessToken,
  setTokenCookies,
} from '@/lib/auth/jovie-oauth';

export async function GET(request: NextRequest) {
  const accessToken = request.cookies.get(authCookies.accessToken)?.value;
  if (accessToken) {
    const user = await fetchUserInfo(accessToken);
    if (user) return NextResponse.json({ user }, { headers: { 'Cache-Control': 'no-store' } });
  }

  const refreshToken = request.cookies.get(authCookies.refreshToken)?.value;
  if (!refreshToken) {
    return NextResponse.json({ user: null }, { headers: { 'Cache-Control': 'no-store' } });
  }

  try {
    const tokens = await refreshAccessToken(refreshToken);
    const user = await fetchUserInfo(tokens.access_token);
    if (!user) throw new Error('Invalid refreshed access token');
    const response = NextResponse.json({ user }, { headers: { 'Cache-Control': 'no-store' } });
    setTokenCookies(response, { ...tokens, refresh_token: tokens.refresh_token || refreshToken });
    return response;
  } catch {
    const response = NextResponse.json(
      { user: null },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    );
    clearTokenCookies(response);
    return response;
  }
}
