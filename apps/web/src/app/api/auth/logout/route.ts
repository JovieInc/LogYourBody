import { NextResponse } from 'next/server';
import { clearTokenCookies } from '@/lib/auth/jovie-oauth';

export async function POST() {
  const response = NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
  clearTokenCookies(response);
  return response;
}
