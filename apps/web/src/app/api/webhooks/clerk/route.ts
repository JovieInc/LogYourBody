import { headers } from 'next/headers';
import { NextRequest, NextResponse } from 'next/server';
import { handleClerkProfileWebhook } from '@/lib/ports/clerk-profile-webhook';

export async function POST(req: NextRequest) {
  const headerPayload = await headers();
  const payload = await req.json();

  const response = await handleClerkProfileWebhook(payload, {
    svixId: headerPayload.get('svix-id'),
    svixTimestamp: headerPayload.get('svix-timestamp'),
    svixSignature: headerPayload.get('svix-signature'),
  });

  return new NextResponse(response.body, { status: response.status });
}
