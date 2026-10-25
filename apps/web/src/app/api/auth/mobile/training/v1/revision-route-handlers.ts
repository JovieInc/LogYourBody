import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import { loadTrainingRecords } from '@/lib/training/service';
import { cycleBlock, cycleReuseOptions } from '@/lib/training/cycle-lifecycle';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import {
  canSteer,
  currentTrainingSetup,
  createDelegatedProposal,
  decideDelegatedProposal,
} from '@/lib/training/delegated-revisions';
import { EXERCISE_CATALOG } from '@/lib/training/catalog';
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
  delegatedEnabled?: () => boolean;
  records?: NativeProductRecordsPort;
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
      : kind === 'adult_profile_required' || kind === 'unauthorized_actor'
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
      const subject = request.nextUrl.searchParams.get('owner') ?? owner.sub;
      const delegated = deps.delegatedEnabled?.() === true && Boolean(deps.records);
      const actor = {
        kind: subject === owner.sub ? ('user' as const) : ('trainer' as const),
        subject: owner.sub,
      };
      if (subject !== owner.sub) {
        if (!delegated) return error('unauthorized_actor');
        const context = await deps.revisions.readContext(subject);
        const setup = context ? (currentTrainingSetup(context) ?? null) : null;
        if (!canSteer(subject, actor, setup)) return error('unauthorized_actor');
      }
      if (action === 'read') {
        if (request.nextUrl.searchParams.get('history') === 'true' && delegated)
          return json({ history: await deps.revisions.exportForSubject(subject) });
        const id = request.nextUrl.searchParams.get('id');
        if (id !== null) {
          if (!z.string().uuid().safeParse(id).success) return error('invalid_request');
          const stored = await deps.revisions.readProposal(subject, id);
          return stored ? json({ stored }) : error('proposal_not_found');
        }
        const context = await deps.revisions.readContext(subject);
        const snapshot = deps.records ? await loadTrainingRecords(deps.records, subject) : null;
        const setup = context ? currentTrainingSetup(context) : null;
        const canonicalInputs =
          context?.canonicalTrainingInputs && typeof context.canonicalTrainingInputs === 'object'
            ? context.canonicalTrainingInputs
            : {};
        const history =
          context && delegated ? await deps.revisions.exportForSubject(subject) : null;
        return context
          ? json({
              generation: context.generation,
              headRevision: context.headRevision,
              supportedIntent: 'initial_enrollment',
              ...(deps.records
                ? {
                    supportedIntents: ['initial_enrollment', 'revise_cycle', 'repeat_cycle'],
                    setup: snapshot?.setup ?? null,
                    cycle: snapshot?.setup
                      ? cycleBlock(snapshot.setup, snapshot.sessions, snapshot.logs, deps.now())
                      : null,
                    reuseOptions: snapshot ? cycleReuseOptions(snapshot) : [],
                  }
                : {}),
              supportedBaseline: true,
              ...(delegated
                ? {
                    pendingProposal:
                      history?.proposals
                        .filter(
                          (s) =>
                            s.status === 'proposed' &&
                            s.proposal.version === 2 &&
                            s.proposal.context.generation === context.generation &&
                            s.proposal.inputEvidence.fingerprint === context.evidenceFingerprint,
                        )
                        .at(-1) ?? null,
                    history:
                      history?.proposals.flatMap((s) =>
                        s.status === 'applied' && s.receipt?.revisionId && s.proposal.version === 2
                          ? [
                              {
                                revisionId: s.receipt.revisionId,
                                reason: s.proposal.reason,
                                summary: s.proposal.summary,
                              },
                            ]
                          : [],
                      ) ?? [],
                  }
                : {}),
              ...(delegated
                ? {
                    delegatedProgramming: true,
                    knownInputs: setup?.delegated?.inputs ?? {
                      ...canonicalInputs,
                      ...(setup
                        ? { sessionsPerWeek: setup.sessionsPerWeek, equipment: setup.equipment }
                        : {}),
                    },
                    currentSetup: setup ?? null,
                    movements: EXERCISE_CATALOG.map((v) => ({ id: v.id, name: v.name })),
                    limitations: [...new Set(EXERCISE_CATALOG.flatMap((v) => v.exclusions))],
                  }
                : {}),
            })
          : error('owner_missing');
      }
      const body = await request.json().catch(() => null);
      const isDelegated =
        action === 'create'
          ? !['initial_enrollment', 'revise_cycle', 'repeat_cycle'].includes(body?.intent?.kind)
          : typeof body?.proposalId === 'string' &&
            (await deps.revisions.readProposal(subject, body.proposalId))?.proposal.version === 2;
      if (isDelegated) {
        if (!delegated || !deps.records) return error('unsupported_or_invalid_intent');
        const input = {
          revisions: deps.revisions,
          records: deps.records,
          subject,
          actor,
          body,
          now: deps.now(),
        };
        const result =
          action === 'create'
            ? await createDelegatedProposal(input)
            : await decideDelegatedProposal(input);
        if (result.kind === 'stored') return json({ stored: result.stored }, 201);
        if (result.kind === 'decided') return json({ receipt: result.receipt });
        if (result.kind === 'question') return json(result);
        return error(result.kind);
      }
      if (subject !== owner.sub) return error('unauthorized_actor');
      const input = {
        revisions: deps.revisions,
        records: deps.records,
        subject: owner.sub,
        body,
        now: deps.now(),
      };
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
