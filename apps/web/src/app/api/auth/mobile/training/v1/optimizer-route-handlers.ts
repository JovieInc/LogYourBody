import { NextRequest, NextResponse } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import {
  decideMesocycleOptimization,
  proposeMesocycleOptimization,
} from '@/lib/training/optimizer-review';
import type { OptimizationProposal } from '@/lib/training/optimizer';

type Dependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  coachEnabled: () => boolean;
  optimizerEnabled: () => boolean;
};

function json(value: unknown, status = 200) {
  return NextResponse.json(
    { version: 1, ...(value as object) },
    { status, headers: { 'Cache-Control': 'no-store' } },
  );
}

/**
 * Proposal endpoint for mesocycle optimization. Both gates default off.
 * The handler has no revision or record port: accepting a diff does not enroll
 * a program and does not write over the user's plan.
 */
export function createTrainingOptimizerHandlers(deps: Dependencies) {
  async function authorized(request: NextRequest) {
    const owner = await deps.authenticate(request);
    if (!owner) return { response: json({ error: 'unauthorized' }, 401) };
    if (!deps.coachEnabled() || !deps.optimizerEnabled()) {
      return { response: json({ error: 'not_found' }, 404) };
    }
    const limit = await deps.reserveRequest(owner.sub);
    if (!limit.allowed) {
      return {
        response: NextResponse.json(
          { version: 1, error: 'rate_limited' },
          {
            status: 429,
            headers: {
              'Cache-Control': 'no-store',
              'Retry-After': String(limit.retryAfterSeconds),
            },
          },
        ),
      };
    }
    return { owner };
  }

  return {
    POST: async (request: NextRequest) => {
      const gate = await authorized(request);
      if (gate.response) return gate.response;
      const body = await request.json().catch(() => null);
      const result = proposeMesocycleOptimization(body, true);
      if (result.kind === 'proposal') return json({ proposal: result.proposal, persisted: false });
      if (result.kind === 'not_certified') {
        return json({ error: 'not_certified', violations: result.violations }, 409);
      }
      return json({ error: 'invalid_request' }, 400);
    },
    PATCH: async (request: NextRequest) => {
      const gate = await authorized(request);
      if (gate.response) return gate.response;
      const body = (await request.json().catch(() => null)) as {
        source?: unknown;
        proposal?: OptimizationProposal;
        decision?: 'apply' | 'reject';
        currentFingerprint?: string;
      } | null;
      if (
        !body ||
        (body.decision !== 'apply' && body.decision !== 'reject') ||
        typeof body.currentFingerprint !== 'string' ||
        !body.proposal
      ) {
        return json({ error: 'invalid_request' }, 400);
      }
      const result = decideMesocycleOptimization({
        source: body.source,
        proposal: body.proposal,
        decision: body.decision,
        currentFingerprint: body.currentFingerprint,
        enabled: true,
      });
      if (result.kind === 'accepted') {
        return json({ receipt: result.receipt, changes: result.changes, persisted: false });
      }
      if (result.kind === 'rejected') return json({ receipt: result.receipt, persisted: false });
      if (result.kind === 'not_certified') {
        return json({ error: result.kind, violations: result.violations }, 409);
      }
      const status = result.kind === 'invalid' ? 400 : 409;
      return json({ error: result.kind }, status);
    },
  };
}
