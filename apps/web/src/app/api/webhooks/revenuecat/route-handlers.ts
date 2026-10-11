import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import type { RevenueEventStore } from '@/lib/ports/revenue-events';
import { revenueCatEnvelopeSchema } from '@/lib/revenuecat/events';

export const MAX_REVENUECAT_BODY_BYTES = 128 * 1024;
const SIGNATURE_TOLERANCE_SECONDS = 300;

type Dependencies = {
  store: RevenueEventStore;
  configuration: () => { signingSecret: string; allowedAppIds: string[] };
  now: () => Date;
};

function reply(status: number, result: string) {
  return Response.json({ result }, { status, headers: { 'Cache-Control': 'no-store' } });
}

async function boundedBody(request: Request): Promise<Buffer | null> {
  if (!request.body) return Buffer.alloc(0);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return Buffer.concat(chunks, size);
      size += value.byteLength;
      if (size > MAX_REVENUECAT_BODY_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
}

function verifies(body: Buffer, header: string | null, secret: string, now: Date) {
  const match = header?.match(/^t=(\d{1,12}),\s*v1=([a-fA-F0-9]{64})$/);
  if (!match) return false;
  const signedAt = Number(match[1]);
  if (Math.abs(now.getTime() / 1000 - signedAt) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = createHmac('sha256', secret).update(`${match[1]}.`).update(body).digest();
  return timingSafeEqual(expected, Buffer.from(match[2]!, 'hex'));
}

export function createRevenueCatHandler(dependencies: Dependencies) {
  return async function POST(request: Request): Promise<Response> {
    const { signingSecret, allowedAppIds } = dependencies.configuration();
    if (!signingSecret.trim() || allowedAppIds.length === 0) return reply(503, 'not_configured');
    if (request.headers.get('content-type')?.split(';')[0]?.trim() !== 'application/json')
      return reply(415, 'unsupported_content_type');
    let body: Buffer | null;
    try {
      body = await boundedBody(request);
    } catch {
      return reply(400, 'invalid_body');
    }
    if (!body) return reply(413, 'body_too_large');
    if (
      !verifies(
        body,
        request.headers.get('x-revenuecat-webhook-signature'),
        signingSecret,
        dependencies.now(),
      )
    )
      return reply(401, 'invalid_signature');
    let parsed: ReturnType<typeof revenueCatEnvelopeSchema.safeParse>;
    try {
      parsed = revenueCatEnvelopeSchema.safeParse(JSON.parse(body.toString('utf8')));
    } catch {
      return reply(400, 'invalid_event');
    }
    if (!parsed.success) return reply(400, 'invalid_event');
    if (!allowedAppIds.includes(parsed.data.event.app_id)) return reply(403, 'app_not_allowed');
    // Zod emits known keys in schema order. Formatting and unknown attributes do
    // not change the fingerprint; changes to persisted reporting fields do.
    const fingerprint = createHash('sha256').update(JSON.stringify(parsed.data)).digest('hex');
    try {
      const result = await dependencies.store.insert(parsed.data, fingerprint);
      return result === 'conflict' ? reply(409, 'event_conflict') : reply(200, result);
    } catch {
      return reply(503, 'storage_unavailable');
    }
  };
}
