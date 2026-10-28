import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import {
  nativeAccountFailureStatus,
  requireNativeAccountAdmission,
  type NativeAccountAdmission,
  type NativeAccountAdmissionPort,
} from '@/lib/ports/native-account-admission';
import type { CanvasLedgerPort, PlanOperation } from '@/lib/training/mesocycle-canvas';
import {
  decideCanvasProposal,
  interpretPlanUtterance,
  proposeCanvasEdit,
  readCanvas,
  amendCanvasProposal,
} from '@/lib/training/mesocycle-canvas';

type Dependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  accounts: NativeAccountAdmissionPort;
  ledgerForAccount: (admission: NativeAccountAdmission) => CanvasLedgerPort;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  now: () => Date;
  enabled: () => boolean;
};

const writeToken = z.number().int().nonnegative().nullable();
const requestSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('read'), expectedWrite: writeToken.optional() }).strict(),
  z
    .object({
      action: z.literal('submit'),
      transcript: z.string().trim().min(1).max(500),
      expectedWrite: writeToken,
    })
    .strict(),
  z
    .object({
      action: z.literal('propose'),
      operation: z.unknown(),
      expectedWrite: writeToken,
    })
    .strict(),
  z
    .object({
      action: z.literal('decide'),
      proposalId: z.string().uuid(),
      decision: z.enum(['apply', 'reject']),
      expectedWrite: writeToken,
    })
    .strict(),
  z
    .object({
      action: z.literal('amend'),
      proposalId: z.string().uuid(),
      instanceId: z.string().min(1),
      sets: z.number().int(),
      expectedWrite: writeToken,
    })
    .strict(),
]);

function json(value: unknown, status = 200) {
  return NextResponse.json(
    { version: 1, ...(value as object) },
    { status, headers: { 'Cache-Control': 'no-store' } },
  );
}

function commandStatus(kind: string): number {
  return kind === 'read' || kind === 'proposed' || kind === 'decided' ? 200 : 409;
}

export function createCanvasRouteHandlers(deps: Dependencies) {
  return {
    async POST(request: NextRequest) {
      const owner = await deps.authenticate(request);
      if (!owner) return json({ error: 'unauthorized' }, 401);
      if (!deps.enabled()) return json({ error: 'not_found' }, 404);
      try {
        // Capture once before rate limiting or body reads; never adopt a recreated owner.
        const admission = requireNativeAccountAdmission(await deps.accounts.capture(owner.sub));
        const ledger = deps.ledgerForAccount(admission);
        const limit = await deps.reserveRequest(owner.sub);
        if (!limit.allowed) {
          return NextResponse.json(
            { version: 1, error: 'rate_limited' },
            {
              status: 429,
              headers: {
                'Cache-Control': 'no-store',
                'Retry-After': String(limit.retryAfterSeconds),
              },
            },
          );
        }
        const body = requestSchema.safeParse(await request.json().catch(() => null));
        if (!body.success) return json({ error: 'invalid_request' }, 400);
        const now = deps.now().toISOString();
        if (body.data.action === 'read') {
          const result = await readCanvas(ledger, owner.sub);
          return json(result, result.kind === 'ledger_invalid' ? 503 : 200);
        }
        if (body.data.action === 'submit') {
          const operation = interpretPlanUtterance(body.data.transcript);
          if (!operation)
            return json({ error: 'unsupported_or_invalid_intent', applied: false }, 400);
          const result = await proposeCanvasEdit(ledger, owner.sub, {
            requestId: crypto.randomUUID(),
            expectedWrite: body.data.expectedWrite,
            operation,
            now,
          });
          return json({ ...result, applied: false }, commandStatus(result.kind));
        }
        if (body.data.action === 'propose') {
          const result = await proposeCanvasEdit(ledger, owner.sub, {
            requestId: crypto.randomUUID(),
            expectedWrite: body.data.expectedWrite,
            operation: body.data.operation as PlanOperation,
            now,
          });
          return json(result, commandStatus(result.kind));
        }
        if (body.data.action === 'amend') {
          const result = await amendCanvasProposal(ledger, owner.sub, body.data);
          return json(result, commandStatus(result.kind));
        }
        const result = await decideCanvasProposal(ledger, owner.sub, {
          requestId: crypto.randomUUID(),
          proposalId: body.data.proposalId,
          decision: body.data.decision,
          expectedWrite: body.data.expectedWrite,
          now,
        });
        return json(result, commandStatus(result.kind));
      } catch (error) {
        const status = nativeAccountFailureStatus(error);
        if (status) return json({ error: (error as Error).message }, status);
        return json({ error: 'training_unavailable' }, 503);
      }
    },
  };
}
