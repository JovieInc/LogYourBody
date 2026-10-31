import 'server-only';
import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { CustomerVoiceHandoff, CustomerVoiceStore } from '@/lib/ports/customer-voice';
import {
  customerVoiceEventSchema,
  isCanarySender,
  privateSupportSummary,
  type CustomerVoiceEvent,
} from './event';

export type CaptureInput = {
  id?: string;
  channel: CustomerVoiceEvent['channel'];
  receivedAt: string;
  text: string;
  subject?: string;
  sender?: string;
  replyable?: boolean;
};

export function createCustomerVoiceCapture(deps: {
  store: CustomerVoiceStore;
  handoff: CustomerVoiceHandoff;
  salt: () => string | undefined;
}) {
  return async (input: CaptureInput) => {
    const salt = deps.salt();
    if (!salt) throw new Error('Missing CUSTOMER_VOICE_SALT');
    const sender = input.sender?.trim().toLowerCase() ?? null;
    if (sender !== null && !z.string().email().max(254).safeParse(sender).success)
      throw new Error('Invalid sender');
    const summary = privateSupportSummary(input.text, input.subject);
    const event = customerVoiceEventSchema.parse({
      schema: 'company.customer-voice/v1',
      app: 'logyourbody',
      id: input.id ?? randomUUID(),
      channel: input.channel,
      receivedAt: input.receivedAt,
      ...summary,
      who: 'LogYourBody customer',
      replyable: Boolean(sender && input.replyable !== false),
      urgent: summary.urgentReasons.length > 0,
      test: isCanarySender(sender),
    });
    // Persist before network I/O. No raw message, subject, health context or identity lookup.
    const saved = await deps.store.insert({
      event,
      senderHash: sender ? createHash('sha256').update(sender).update(salt).digest('hex') : null,
      replyTo: event.replyable ? sender : null,
      stages: { received: event.receivedAt },
    });
    if (saved.stages.forwarded) return { id: saved.event.id, handoff: 'forwarded' as const };
    let result: { pingedAt?: string };
    try {
      result = await deps.handoff.forward(saved.event);
    } catch {
      await deps.store.stage(saved.event.id, 'handoff-unavailable', new Date().toISOString());
      return { id: saved.event.id, handoff: 'unavailable' as const };
    }
    await deps.store.stage(saved.event.id, 'forwarded', new Date().toISOString());
    if (result.pingedAt) await deps.store.stage(saved.event.id, 'pinged', result.pingedAt);
    return { id: saved.event.id, handoff: 'forwarded' as const };
  };
}
