import type { CustomerVoiceEvent } from '@/lib/customer-voice/event';

export type VoiceStage =
  | 'received'
  | 'forwarded'
  | 'pinged'
  | 'approved'
  | 'sent'
  | 'handoff-unavailable'
  | 'sending'
  | 'send-failed';
export type VoiceItem = {
  event: CustomerVoiceEvent;
  senderHash: string | null;
  replyTo: string | null;
  stages: Partial<Record<VoiceStage, string>>;
};

export interface CustomerVoiceStore {
  /** Returns the immutable existing item on redelivery. */
  insert(item: VoiceItem): Promise<VoiceItem>;
  get(id: string): Promise<VoiceItem | null>;
  stage(id: string, stage: VoiceStage, at: string): Promise<void>;
  /** Atomic once-only send claim, including the approval receipt. */
  claimReply(
    id: string,
    receipt: { approvedAt: string; approvalKey: string; draftSha256: string },
  ): Promise<boolean>;
}

export interface CustomerVoiceHandoff {
  forward(event: CustomerVoiceEvent): Promise<{ pingedAt?: string }>;
}

export interface CustomerVoiceEmailTransport {
  /** Must deduplicate idempotencyKey. The recipient is read from the original row. */
  send(input: { to: string; text: string; idempotencyKey: string }): Promise<void>;
}
