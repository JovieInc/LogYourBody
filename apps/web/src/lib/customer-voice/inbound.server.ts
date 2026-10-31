import 'server-only';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import type { CaptureInput } from './capture.server';
import { isAutomatedEmail } from './classify';
import { boundedBody, voiceJson } from './http.server';

const inboundSchema = z
  .object({
    id: z.string().uuid(),
    receivedAt: z.string().datetime(),
    from: z.string().email().max(254),
    text: z.string().max(64000),
    subject: z.string().max(200).optional(),
    automated: z.boolean().optional(),
  })
  .strict();

export function verifyInboundHmac(body: Buffer, signature: string | null, secret: string): boolean {
  if (!secret || !signature || !/^sha256=[a-f0-9]{64}$/.test(signature)) return false;
  return timingSafeEqual(
    createHmac('sha256', secret).update(body).digest(),
    Buffer.from(signature.slice(7), 'hex'),
  );
}

export function createInboundVoiceHandler(deps: {
  secret: () => string | undefined;
  capture: (input: CaptureInput) => Promise<{ id: string; handoff: string }>;
}) {
  return async (request: Request) => {
    const secret = deps.secret();
    if (!secret) return voiceJson({ code: 'inbound-unavailable' }, 503);
    let raw: Buffer | null;
    try {
      raw = await boundedBody(request);
    } catch {
      return voiceJson({ code: 'invalid-body' }, 400);
    }
    if (!raw) return voiceJson({ code: 'body-too-large' }, 413);
    if (!verifyInboundHmac(raw, request.headers.get('x-customer-voice-signature'), secret))
      return voiceJson({ code: 'unauthorized' }, 401);
    let parsed: ReturnType<typeof inboundSchema.safeParse>;
    try {
      parsed = inboundSchema.safeParse(JSON.parse(raw.toString('utf8')));
    } catch {
      return voiceJson({ code: 'invalid-body' }, 400);
    }
    if (!parsed.success) return voiceJson({ code: 'invalid-body' }, 400);
    const input = parsed.data;
    try {
      const result = await deps.capture({
        id: input.id,
        channel: 'email',
        receivedAt: input.receivedAt,
        text: input.text,
        subject: input.subject,
        sender: input.from,
        replyable:
          !input.automated && !isAutomatedEmail({ from: input.from, subject: input.subject }),
      });
      return voiceJson(result, 202);
    } catch {
      return voiceJson({ code: 'capture-unavailable' }, 503);
    }
  };
}
