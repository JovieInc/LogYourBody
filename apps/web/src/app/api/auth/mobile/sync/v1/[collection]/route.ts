import type { NextRequest } from 'next/server';
import { authCookies } from '@/lib/auth/constants';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { createNativeProductRecordHandlers } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  if (bearer) return fetchUserInfo(bearer);
  const cookieToken = request.cookies.get(authCookies.accessToken)?.value;
  return cookieToken ? fetchUserInfo(cookieToken) : null;
}

const handlers = createNativeProductRecordHandlers({
  authenticate,
  records: neonNativeProductRecords,
});

export const GET = handlers.GET;
export const POST = handlers.POST;
export const DELETE = handlers.DELETE;
