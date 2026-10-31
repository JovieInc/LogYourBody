import { z } from 'zod';
import { URGENT_REASONS, urgentReasons } from './classify';

export const CHANNELS = ['email', 'chat', 'feedback', 'waitlist_reply', 'review', 'sms'] as const;
export const customerVoiceEventSchema = z
  .object({
    schema: z.literal('company.customer-voice/v1'),
    app: z.literal('logyourbody'),
    id: z.string().uuid(),
    channel: z.enum(CHANNELS),
    receivedAt: z.string().datetime(),
    text: z.string().min(1).max(4000),
    subject: z.string().max(200).optional(),
    who: z
      .string()
      .min(1)
      .max(200)
      .regex(/^[^\r\n]+$/),
    name: z
      .string()
      .max(32)
      .regex(/^[\p{L}'-]+$/u)
      .optional(),
    replyable: z.boolean(),
    urgent: z.boolean(),
    urgentReasons: z.array(z.enum(URGENT_REASONS)).max(5),
    test: z.boolean(),
  })
  .strict();
export type CustomerVoiceEvent = z.infer<typeof customerVoiceEventSchema>;

export const SUMMARY_PREFIX = 'Customer message received. Details withheld for health privacy.';

/** Never attempt regex health-data redaction: arbitrary prose cannot be proven safe.
 * Only fixed support categories cross the support persistence/Summer boundary.
 */
export function privateSupportSummary(text: string, subject = '') {
  const reasons = urgentReasons(`${subject}\n${text}`);
  const labels = {
    bug: 'bug report',
    billing: 'billing question',
    angry: 'unacceptable experience',
    public: 'posting about app',
    legal: 'legal action or privacy request',
  };
  return {
    text: `${SUMMARY_PREFIX}${reasons.length ? ` Support categories: ${reasons.map((reason) => labels[reason]).join(', ')}.` : ''}`,
    urgentReasons: reasons,
  };
}

export function isCanarySender(email: string | null): boolean {
  return email !== null && /^browse-ready\+.*@jov\.ie$/i.test(email);
}
