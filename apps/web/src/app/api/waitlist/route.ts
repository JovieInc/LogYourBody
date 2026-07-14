import { NextRequest, NextResponse } from 'next/server';
import { upsertWaitlistEntry } from '@/lib/waitlist/store';

export const runtime = 'nodejs';

const NO_STORE_HEADERS = { 'Cache-Control': 'no-store' } as const;

export async function POST(request: NextRequest) {
  try {
    const body = (await request.json()) as { email?: unknown; source?: unknown };
    const email = typeof body.email === 'string' ? body.email : '';
    const source = typeof body.source === 'string' ? body.source : 'landing';

    if (!email.trim()) {
      return NextResponse.json(
        { success: false, error: 'Email is required' },
        { status: 400, headers: NO_STORE_HEADERS },
      );
    }

    const result = await upsertWaitlistEntry({ email, source });

    return NextResponse.json(
      {
        success: true,
        status: result.status,
        id: result.id,
      },
      { status: result.status === 'created' ? 201 : 200, headers: NO_STORE_HEADERS },
    );
  } catch (error) {
    if (error instanceof Error && error.message === 'INVALID_EMAIL') {
      return NextResponse.json(
        { success: false, error: 'Invalid email address' },
        { status: 400, headers: NO_STORE_HEADERS },
      );
    }

    console.error('[api/waitlist] Failed to persist waitlist entry', error);
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500, headers: NO_STORE_HEADERS },
    );
  }
}
