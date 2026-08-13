import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

export async function POST(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) {
    return NextResponse.json(
      { error: 'unauthorized' },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  // Cloudinary is the canonical non-Supabase blob store, but its credentials
  // lived only on the retired Supabase function secret plane. Do not invent a
  // new CDN. New remote photo uploads fail closed; Core Data remains local.
  return NextResponse.json(
    {
      error: 'photo_store_unavailable',
      message:
        'Progress photo cloud storage is not available. Photos stay on this device until Cloudinary is configured on the first-party API.',
    },
    { status: 503, headers: { 'Cache-Control': 'no-store' } },
  );
}
