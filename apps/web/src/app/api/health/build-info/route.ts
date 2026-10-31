import { NextResponse } from 'next/server';
import { buildOpsHealth } from '@/lib/ops-health';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  return NextResponse.json(
    buildOpsHealth({
      VERCEL_GIT_COMMIT_SHA: process.env.VERCEL_GIT_COMMIT_SHA,
      VERCEL_ENV: process.env.VERCEL_ENV,
      NEXT_PUBLIC_APP_VERSION: process.env.NEXT_PUBLIC_APP_VERSION,
      OPS_BUILD_TIME: process.env.OPS_BUILD_TIME,
    }),
    { headers: { 'cache-control': 'private, no-cache, no-store, must-revalidate' } },
  );
}
