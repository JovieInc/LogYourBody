import { verifySummerOidcRequest } from '@/lib/adapters/customer-voice-summer.server';
import { readPublicLandingGate } from '@/lib/adapters/StatsigPublicLandingAdapter.server';
import {
  createApprovedReplySender,
  createCustomerVoiceReplyHandler,
} from '@/lib/customer-voice/reply.server';
import { neonCustomerVoice } from '@/lib/neon/customer-voice-adapter';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const POST = createCustomerVoiceReplyHandler({
  authenticate: verifySummerOidcRequest,
  send: createApprovedReplySender({
    store: neonCustomerVoice,
    transport: null,
    enabled: () => readPublicLandingGate('lyb_customer_voice_replies'),
  }),
});
