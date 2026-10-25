import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import { gymChangesSchema, type GymRegistryPort } from '@/lib/ports/gym-registry';
import { nativeAccountFailureStatus } from '@/lib/ports/native-account-admission';
import { CATALOG_EQUIPMENT, queryExerciseLibrary } from '@/lib/training/catalog';

export function createGymRegistryHandlers(deps: {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  enabled: () => boolean;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  registry: GymRegistryPort;
}) {
  const json = (payload: object, status = 200, headers = {}) =>
    NextResponse.json(
      { version: 1, ...payload },
      { status, headers: { 'Cache-Control': 'no-store', ...headers } },
    );
  async function handle(request: NextRequest, action: 'read' | 'sync' | 'exercises') {
    const identity = await deps.authenticate(request);
    if (!identity) return json({ error: 'unauthorized' }, 401);
    if (!deps.enabled()) return json({ error: 'not_found' }, 404);
    const rate = await deps.reserveRequest(identity.sub);
    if (!rate.allowed)
      return json({ error: 'rate_limited' }, 429, {
        'Retry-After': String(rate.retryAfterSeconds),
      });
    try {
      if (action === 'exercises') {
        const params = request.nextUrl.searchParams;
        if ([...params.keys()].some((key) => key !== 'equipment'))
          return json({ error: 'invalid_filter' }, 400);
        const raw = params.getAll('equipment');
        const parsed = z
          .array(z.enum(CATALOG_EQUIPMENT))
          .safeParse(raw.filter((item) => item !== ''));
        if (!parsed.success) return json({ error: 'invalid_filter' }, 400);
        const equipment = params.has('equipment') ? new Set(parsed.data) : null;
        return json({
          exercises: queryExerciseLibrary({ equipment }).map(({ id, name, requires }) => ({
            id,
            name,
            requires,
          })),
        });
      }
      if (action === 'read') return json({ gyms: await deps.registry.sync(identity.sub) });
      const parsed = gymChangesSchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return json({ error: 'invalid_gyms' }, 400);
      return json({ gyms: await deps.registry.sync(identity.sub, parsed.data.changes) });
    } catch (error) {
      return json({ error: 'gym_registry_unavailable' }, nativeAccountFailureStatus(error) ?? 503);
    }
  }
  return {
    GET: (request: NextRequest) => handle(request, 'read'),
    POST: (request: NextRequest) => handle(request, 'sync'),
    exercises: (request: NextRequest) => handle(request, 'exercises'),
  };
}
