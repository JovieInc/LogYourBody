import type { NextRequest } from 'next/server';
import { randomUUID } from 'node:crypto';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { createVoiceProviders, getVoiceProviderId } from '@/lib/voice/providers';
import { createVoiceRouteHandlers } from './route-handlers';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

const providers = createVoiceProviders({
  elevenLabsApiKey: process.env.ELEVENLABS_API_KEY,
  aiGatewayApiKey: process.env.AI_GATEWAY_API_KEY,
});

export const voiceHandlers = createVoiceRouteHandlers({
  authenticate,
  createRequestId: randomUUID,
  enabled: () => process.env.LYB_VOICE_ENABLED === 'true',
  provider: () => {
    const providerId = getVoiceProviderId(process.env.LYB_VOICE_PROVIDER);
    return providerId ? providers[providerId] : null;
  },
  voiceId: () => process.env.LYB_VOICE_ID ?? 'A4j35F5T4XsPMeXd06Pm',
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
});
