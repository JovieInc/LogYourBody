import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { GymSchema, type GymRegistryPort } from '@/lib/ports/gym-registry';
import {
  nativeAccountFailureStatus,
  requireNativeAccountAdmission,
  type NativeAccountAdmissionPort,
} from '@/lib/ports/native-account-admission';

type Dependencies = {
  authenticate(request: NextRequest): Promise<JovieUserInfo | null>;
  registry: GymRegistryPort;
  accounts: NativeAccountAdmissionPort;
};

export function createGymRegistryHandlers(deps: Dependencies) {
  const json = (body: unknown, status = 200) =>
    NextResponse.json(body, {
      status,
      headers: { 'Cache-Control': 'no-store' },
    });
  async function handle(request: NextRequest, method: 'GET' | 'POST' | 'DELETE') {
    const identity = await deps.authenticate(request);
    if (!identity) return json({ error: 'unauthorized' }, 401);
    try {
      if (method === 'GET') return json({ gyms: await deps.registry.list(identity.sub) });
      const admission = requireNativeAccountAdmission(await deps.accounts.capture(identity.sub));
      const body: unknown = await request.json().catch(() => null);
      if (method === 'POST') {
        const parsed = GymSchema.safeParse(body);
        if (!parsed.success) return json({ error: 'invalid_gym' }, 400);
        if (!(await deps.registry.save(admission, parsed.data)))
          return json({ error: 'gym_conflict' }, 409);
        return json({ gym: parsed.data });
      }
      const parsed = z.object({ id: z.string().uuid() }).strict().safeParse(body);
      if (!parsed.success) return json({ error: 'invalid_gym' }, 400);
      await deps.registry.remove(admission, parsed.data.id);
      return json({ deleted: parsed.data.id });
    } catch (error) {
      const status = nativeAccountFailureStatus(error);
      if (status === null) throw error;
      return json({ error: 'account_changed' }, status);
    }
  }
  return {
    GET: (request: NextRequest) => handle(request, 'GET'),
    POST: (request: NextRequest) => handle(request, 'POST'),
    DELETE: (request: NextRequest) => handle(request, 'DELETE'),
  };
}
