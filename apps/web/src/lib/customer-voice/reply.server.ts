import 'server-only';
import { createHash } from 'node:crypto';
import { z } from 'zod';
import type { CustomerVoiceEmailTransport, CustomerVoiceStore } from '@/lib/ports/customer-voice';
import { boundedBody, voiceJson } from './http.server';

export const customerReplySchema = z
  .object({
    text: z.string().min(2).max(4000),
    draftSha256: z.string().regex(/^[a-f0-9]{64}$/),
    approvedAt: z.string().datetime(),
    approvalKey: z.string().min(8).max(128),
  })
  .strict();
export type CustomerReplyInput = z.infer<typeof customerReplySchema>;

export function createApprovedReplySender(deps: {
  store: CustomerVoiceStore;
  transport: CustomerVoiceEmailTransport | null;
  enabled: () => Promise<boolean>;
}) {
  return async (id: string, input: CustomerReplyInput) => {
    const item = await deps.store.get(id);
    if (!item) return { code: 'not-found', status: 404 };
    if (!item.event.replyable || !item.replyTo) return { code: 'not-replyable', status: 422 };
    if (item.stages.sent || item.stages.sending)
      return { code: 'already-sent-or-claimed', status: 409 };
    if (createHash('sha256').update(input.text).digest('hex') !== input.draftSha256)
      return { code: 'draft-mismatch', status: 422 };
    if (Date.parse(input.approvedAt) > Date.now() + 60000)
      return { code: 'invalid-approval', status: 422 };
    // No claim/approval/sent timestamps for unavailable delivery: never fake a send.
    if (!deps.transport) return { code: 'no-email-transport', status: 501 };
    if (!(await deps.enabled())) return { code: 'reply-gate-closed', status: 503 };
    if (
      !(await deps.store.claimReply(id, {
        approvedAt: input.approvedAt,
        approvalKey: input.approvalKey,
        draftSha256: input.draftSha256,
      }))
    )
      return { code: 'already-sent-or-claimed', status: 409 };
    try {
      await deps.transport.send({
        to: item.replyTo,
        text: input.text,
        idempotencyKey: `customer-voice-reply:${id}`,
      });
    } catch {
      // Keep the claim on ambiguous provider failures: retry must not double-send.
      await deps.store.stage(id, 'send-failed', new Date().toISOString());
      return { code: 'send-failed', status: 502 };
    }
    await deps.store.stage(id, 'sent', new Date().toISOString());
    return { code: 'sent', status: 200 };
  };
}

export function createCustomerVoiceReplyHandler(deps: {
  authenticate: (request: Request) => Promise<boolean>;
  send: ReturnType<typeof createApprovedReplySender>;
}) {
  return async (request: Request, context: { params: Promise<{ id: string }> }) => {
    if (!(await deps.authenticate(request))) return voiceJson({ code: 'unauthorized' }, 401);
    const { id } = await context.params;
    if (!z.string().uuid().safeParse(id).success) return voiceJson({ code: 'invalid-id' }, 400);
    let input: ReturnType<typeof customerReplySchema.safeParse>;
    try {
      const raw = await boundedBody(request, 32 * 1024);
      if (!raw) return voiceJson({ code: 'body-too-large' }, 413);
      input = customerReplySchema.safeParse(JSON.parse(raw.toString('utf8')));
    } catch {
      return voiceJson({ code: 'invalid-body' }, 400);
    }
    if (!input.success) return voiceJson({ code: 'invalid-body' }, 400);
    try {
      const result = await deps.send(id, input.data);
      return voiceJson({ code: result.code }, result.status);
    } catch {
      return voiceJson({ code: 'reply-unavailable' }, 503);
    }
  };
}
