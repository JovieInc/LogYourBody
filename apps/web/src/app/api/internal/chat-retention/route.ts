import { NextRequest, NextResponse } from 'next/server';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  const authorization = request.headers.get('authorization');
  if (!secret || authorization !== `Bearer ${secret}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const purged = await neonChatConversations.purgeExpired();
  return NextResponse.json({ ok: true, purged }, { headers: { 'Cache-Control': 'no-store' } });
}
