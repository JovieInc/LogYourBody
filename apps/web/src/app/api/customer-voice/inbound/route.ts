import { createSummerVoiceHandoff } from '@/lib/adapters/customer-voice-summer.server';
import { createCustomerVoiceCapture } from '@/lib/customer-voice/capture.server';
import { createInboundVoiceHandler } from '@/lib/customer-voice/inbound.server';
import { neonCustomerVoice } from '@/lib/neon/customer-voice-adapter';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const POST = createInboundVoiceHandler({
  secret: () => process.env.CUSTOMER_VOICE_INBOUND_SECRET,
  capture: createCustomerVoiceCapture({
    store: neonCustomerVoice,
    handoff: createSummerVoiceHandoff(),
    salt: () => process.env.CUSTOMER_VOICE_SALT,
  }),
});
