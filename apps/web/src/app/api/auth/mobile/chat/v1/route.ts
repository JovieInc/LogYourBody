import { randomUUID } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { createChatModelPort } from '@/lib/adapters/openai-chat-model-adapter';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { createChatRouteHandlers } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

const handlers = createChatRouteHandlers({
  authenticate,
  conversations: neonChatConversations,
  bodyMetrics: neonBodyMetrics,
  users: neonUserDirectory,
  createModel: createChatModelPort,
  modelName: process.env.LYB_CHAT_MODEL || 'gpt-4o-mini',
  createLeaseToken: randomUUID,
  reportStreamOutcome: (outcome) => console.info('LYB_CHAT_STREAM', { outcome }),
});

export const GET = handlers.GET;
export const POST = handlers.POST;
export const DELETE = handlers.DELETE;
