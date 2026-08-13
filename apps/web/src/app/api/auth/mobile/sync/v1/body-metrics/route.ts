import type { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonNativeBodyMetricsSync } from '@/lib/neon/native-body-metrics-sync-adapter';
import { createNativeBodyMetricsSyncHandlers } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

const handlers = createNativeBodyMetricsSyncHandlers({
  authenticate,
  sync: neonNativeBodyMetricsSync,
});

export const GET = handlers.GET;
export const POST = handlers.POST;
export const DELETE = handlers.DELETE;
