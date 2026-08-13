import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
import { authCookies } from '@/lib/auth/constants';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  if (bearer) return fetchUserInfo(bearer);
  const cookieToken = request.cookies.get(authCookies.accessToken)?.value;
  return cookieToken ? fetchUserInfo(cookieToken) : null;
}

export async function GET(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) {
    return NextResponse.json(
      { error: 'unauthorized' },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const [user, metrics, records] = await Promise.all([
    neonUserDirectory.getUser(identity.sub),
    neonBodyMetrics.list(identity.sub, 100),
    neonNativeProductRecords.listAll(identity.sub),
  ]);

  return NextResponse.json(
    {
      version: 1,
      exported_at: new Date().toISOString(),
      subject: identity.sub,
      profile: user,
      body_metrics: metrics,
      ...records,
    },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function POST(request: NextRequest) {
  return GET(request);
}
