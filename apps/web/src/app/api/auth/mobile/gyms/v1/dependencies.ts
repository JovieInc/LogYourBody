import type { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonGymRegistry } from '@/lib/neon/gym-registry-adapter';
import { createGymRegistryHandlers } from './route-handlers';

export const gymRegistryHandlers = createGymRegistryHandlers({
  authenticate: (request: NextRequest) => {
    const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
    return token ? fetchUserInfo(token) : Promise.resolve(null);
  },
  enabled: () => process.env.LYB_GYM_REGISTRY_ENABLED === 'true',
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  registry: neonGymRegistry,
});
