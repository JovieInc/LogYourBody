import { NextRequest, NextResponse } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { mesocycleCanvasApiEnabled } from '@/lib/flags/mesocycle-canvas';
import { canvasHandlers } from '../../auth/mobile/training/v1/dependencies';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function failure(error: string, status: number) {
  return NextResponse.json({ error }, { status, headers: { 'Cache-Control': 'no-store' } });
}

/** Keep the existing web session credential on the server and native auth bearer-only. */
export async function POST(request: NextRequest) {
  if (!mesocycleCanvasApiEnabled()) return failure('not_found', 404);
  if (request.headers.get('origin') !== request.nextUrl.origin) return failure('forbidden', 403);
  if (
    request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json'
  ) {
    return failure('unsupported_media_type', 415);
  }
  if (request.signal.aborted) return failure('request_cancelled', 499);

  try {
    const session = await getServerAuthSession();
    if (request.signal.aborted) return failure('request_cancelled', 499);
    if (!session.userId) return failure('unauthorized', 401);
    if (request.headers.get('x-lyb-account-subject') !== session.userId) {
      return failure('stale_context', 409);
    }
    const token = await session.getToken();
    if (!token || /\s/.test(token)) return failure('unauthorized', 401);
    const body = await request.text();
    if (request.signal.aborted) return failure('request_cancelled', 499);

    // Do not forward client-supplied credentials, cookies, or routing headers.
    const forwarded = new NextRequest(new URL('/api/auth/mobile/training/v1/canvas', request.url), {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        authorization: `Bearer ${token}`,
      },
      body,
      signal: request.signal,
    });
    return await canvasHandlers.POST(forwarded);
  } catch {
    return failure('training_unavailable', 503);
  }
}
