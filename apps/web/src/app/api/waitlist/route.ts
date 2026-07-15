import { NextRequest, NextResponse } from 'next/server';
import { acceptWaitlistEntry } from '@/lib/waitlist/store';

export const runtime = 'nodejs';

const NO_STORE_HEADERS = { 'Cache-Control': 'no-store' } as const;
const MAX_BODY_BYTES = 4_096;
const SOURCE_PATTERN = /^[a-z0-9:_-]{1,120}$/i;

function response(body: Record<string, unknown>, status: number) {
  return NextResponse.json(body, { status, headers: NO_STORE_HEADERS });
}

export async function POST(request: NextRequest) {
  try {
    if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
      return response({ success: false, error: 'Content-Type must be application/json' }, 415);
    }

    const contentLength = Number(request.headers.get('content-length') ?? 0);
    if (contentLength > MAX_BODY_BYTES) {
      return response({ success: false, error: 'Request body is too large' }, 413);
    }

    const rawBody = await request.text();
    if (rawBody.length > MAX_BODY_BYTES) {
      return response({ success: false, error: 'Request body is too large' }, 413);
    }

    let body: { email?: unknown; source?: unknown; website?: unknown };
    try {
      body = JSON.parse(rawBody) as typeof body;
    } catch {
      return response({ success: false, error: 'Invalid JSON' }, 400);
    }

    // Bots commonly fill visually hidden fields. Return the same accepted
    // response without writing so they cannot tune around the trap.
    if (typeof body.website === 'string' && body.website.trim()) {
      return response({ success: true }, 202);
    }

    const email = typeof body.email === 'string' ? body.email : '';
    const source = typeof body.source === 'string' ? body.source : 'landing:minimal:direct';

    if (!email.trim()) {
      return response({ success: false, error: 'Email is required' }, 400);
    }

    if (!SOURCE_PATTERN.test(source)) {
      return response({ success: false, error: 'Invalid source' }, 400);
    }

    await acceptWaitlistEntry({ email, source });
    return response({ success: true }, 202);
  } catch (error) {
    if (error instanceof Error && error.message === 'INVALID_EMAIL') {
      return response({ success: false, error: 'Invalid email address' }, 400);
    }

    console.error('[api/waitlist] Failed to persist waitlist entry', error);
    return response({ success: false, error: 'Internal server error' }, 500);
  }
}
