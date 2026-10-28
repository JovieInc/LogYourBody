import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import {
  createInitialTrainingProposal,
  decideInitialTrainingProposal,
} from '@/lib/training/revisions';

type Dependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  revisions: TrainingRevisionsPort;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  now: () => Date;
  enabled: () => boolean;
};
function json(value: unknown, status = 200) {
  return NextResponse.json(
    { version: 1, ...(value as object) },
    { status, headers: { 'Cache-Control': 'no-store' } },
  );
}
function error(kind: string) {
  const status =
    kind === 'owner_missing' || kind === 'proposal_not_found'
      ? 404
      : kind === 'adult_profile_required'
        ? 403
        : kind === 'invalid_request' || kind === 'unsupported_or_invalid_intent'
          ? 400
          : 409;
  return json({ error: kind }, status);
}
export function createTrainingRevisionHandlers(deps: Dependencies) {
  async function handle(request: NextRequest, action: 'read' | 'create' | 'decide') {
    const owner = await deps.authenticate(request);
    if (!owner) return json({ error: 'unauthorized' }, 401);
    if (!deps.enabled()) return json({ error: 'not_found' }, 404);
    const limit = await deps.reserveRequest(owner.sub);
    if (!limit.allowed)
      return NextResponse.json(
        { version: 1, error: 'rate_limited' },
        {
          status: 429,
          headers: { 'Cache-Control': 'no-store', 'Retry-After': String(limit.retryAfterSeconds) },
        },
      );
    try {
      if (action === 'read') {
        const id = request.nextUrl.searchParams.get('id');
        if (id !== null) {
          if (!z.string().uuid().safeParse(id).success) return error('invalid_request');
          const stored = await deps.revisions.readProposal(owner.sub, id);
          return stored ? json({ stored }) : error('proposal_not_found');
        }
        const context = await deps.revisions.readContext(owner.sub);
        return context
          ? json({
              generation: context.generation,
              headRevision: context.headRevision,
              supportedIntent: 'initial_enrollment',
              supportedBaseline: true,
            })
          : error('owner_missing');
      }
      const body = await request.json().catch(() => null);
      const input = { revisions: deps.revisions, subject: owner.sub, body, now: deps.now() };
      const result =
        action === 'create'
          ? await createInitialTrainingProposal(input)
          : await decideInitialTrainingProposal(input);
      if (result.kind === 'stored') return json({ stored: result.stored }, 201);
      if (result.kind === 'decided') return json({ receipt: result.receipt });
      return error(result.kind);
    } catch {
      return json({ error: 'training_unavailable' }, 503);
    }
  }
  return {
    GET: (r: NextRequest) => handle(r, 'read'),
    POST: (r: NextRequest) => handle(r, 'create'),
    PATCH: (r: NextRequest) => handle(r, 'decide'),
  };
}
