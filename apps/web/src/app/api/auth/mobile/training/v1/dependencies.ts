import { neonTrainingRevisions } from '@/lib/neon/training-revisions-adapter';
import { createTrainingRevisionHandlers } from './revision-route-handlers';
import { randomUUID } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { createTrainingRouteHandlers } from './route-handlers';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

export const trainingHandlers = createTrainingRouteHandlers({
  authenticate,
  records: neonNativeProductRecords,
  revisions: neonTrainingRevisions,
  users: neonUserDirectory,
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  createId: randomUUID,
  now: () => new Date(),
  enabled: () => process.env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true',
});

export const trainingRevisionHandlers = createTrainingRevisionHandlers({
  authenticate,
  revisions: neonTrainingRevisions,
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  now: () => new Date(),
  enabled: () => process.env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true',
});
