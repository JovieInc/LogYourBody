import { NextRequest, NextResponse } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import {
  recoveryTargetSchema,
  createRecoveryTrialSchema,
  decideRecoveryTrialSchema,
} from '@/lib/training/recovery-contract';
import {
  createRecoveryTrial,
  decideRecoveryTrial,
  readRecovery,
  RecoveryConflict,
} from '@/lib/training/recovery-records';
import { TrainingMutationError } from '@/lib/training/mutation-admission';

export function createRecoveryRouteHandlers(deps: {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  records: NativeProductRecordsPort;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  enabled: () => boolean;
  now: () => Date;
}) {
  const json = (payload: object, status = 200, headers: Record<string, string> = {}) =>
    NextResponse.json(
      { version: 1, ...payload },
      { status, headers: { 'Cache-Control': 'no-store', ...headers } },
    );
  async function handle(request: NextRequest, method: 'GET' | 'POST' | 'PATCH') {
    const identity = await deps.authenticate(request);
    if (!identity) return json({ error: 'unauthorized' }, 401);
    if (!deps.enabled()) return json({ error: 'not_found' }, 404);
    const rate = await deps.reserveRequest(identity.sub);
    if (!rate.allowed)
      return json({ error: 'rate_limited' }, 429, {
        'Retry-After': String(rate.retryAfterSeconds),
      });
    try {
      const base = { records: deps.records, subject: identity.sub, now: deps.now() };
      if (method === 'GET') {
        const parsed = recoveryTargetSchema.safeParse(
          Object.fromEntries(request.nextUrl.searchParams),
        );
        if (!parsed.success) return json({ error: 'invalid_request' }, 400);
        return json(await readRecovery({ ...base, target: parsed.data }));
      }
      const body: unknown = await request.json().catch(() => null);
      if (method === 'POST') {
        const parsed = createRecoveryTrialSchema.safeParse(body);
        if (!parsed.success) return json({ error: 'invalid_request' }, 400);
        const { requestId, ...target } = parsed.data;
        return json({ trial: await createRecoveryTrial({ ...base, requestId, target }) }, 201);
      }
      const parsed = decideRecoveryTrialSchema.safeParse(body);
      if (!parsed.success) return json({ error: 'invalid_request' }, 400);
      return json({ trial: await decideRecoveryTrial({ ...base, ...parsed.data }) });
    } catch (error) {
      if (error instanceof RecoveryConflict) return json({ error: error.message }, 409);
      if (error instanceof TrainingMutationError && error.code === 'training_context_changed')
        return json({ error: error.code }, 409);
      return json({ error: 'training_unavailable' }, 503);
    }
  }
  return {
    GET: (request: NextRequest) => handle(request, 'GET'),
    POST: (request: NextRequest) => handle(request, 'POST'),
    PATCH: (request: NextRequest) => handle(request, 'PATCH'),
  };
}
