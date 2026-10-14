import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { mesocycleCanvasEnabled } from '@/lib/flags/mesocycle-canvas';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { createNeonCanvasPort } from '@/lib/neon/training-canvas-adapter';
import { createMemoryCanvasPort, type CanvasPort } from '@/lib/training/mesocycle-canvas';
import { createMesocycleCanvasHandlers } from '../mesocycle-canvas-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const memoryPort = createMemoryCanvasPort(null);

function canvasPort(): CanvasPort {
  return process.env.LYB_MESOCYCLE_CANVAS_STORE === 'memory' ? memoryPort : createNeonCanvasPort();
}

const port: CanvasPort = {
  read: (subject) => canvasPort().read(subject),
  write: (subject, expectedGeneration, journal) =>
    canvasPort().write(subject, expectedGeneration, journal),
};

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

const handlers = createMesocycleCanvasHandlers({
  authenticate,
  port,
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  now: () => new Date(),
  enabled: () => mesocycleCanvasEnabled(),
});

export const GET = handlers.GET;
export const POST = handlers.POST;
