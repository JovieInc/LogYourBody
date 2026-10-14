import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import {
  canvasReadback,
  reviseCanvas,
  type CanvasCommand,
  type CanvasOp,
  type CanvasPort,
  type CanvasResult,
} from '@/lib/training/mesocycle-canvas';

const daySchema = z.enum(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']);
const opSchema = z.discriminatedUnion('kind', [
  z.object({ id: z.string().min(1).max(80), kind: z.literal('draft') }).strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('prioritize'),
      target: z.enum(['upper_chest', 'triceps']),
    })
    .strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('training_days'),
      count: z.literal(5),
    })
    .strict(),
  z
    .object({ id: z.string().min(1).max(80), kind: z.literal('split_day'), day: z.literal('wed') })
    .strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('swap_variant'),
      toVariantId: z.literal('smith_machine_incline_press'),
    })
    .strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('declare_equipment'),
      item: z.string().min(1).max(40),
    })
    .strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('move'),
      instanceId: z.string().min(1).max(120),
      toDay: daySchema,
      toSessionId: z.string().min(1).max(40),
      toIndex: z.number().int().min(0).max(30),
    })
    .strict(),
  z
    .object({
      id: z.string().min(1).max(80),
      kind: z.literal('set_sets'),
      instanceId: z.string().min(1).max(120),
      sets: z.number().int().min(1).max(6),
    })
    .strict(),
  z.object({ id: z.string().min(1).max(80), kind: z.literal('undo') }).strict(),
  z.object({ id: z.string().min(1).max(80), kind: z.literal('redo') }).strict(),
]);

const commandSchema = z.discriminatedUnion('type', [
  z
    .object({
      type: z.literal('propose'),
      requestId: z.string().min(1).max(80),
      expectedGeneration: z.number().int().nonnegative(),
      baseRevisionId: z.string().min(1).max(120).nullable(),
      source: z.enum(['chat', 'voice', 'direct']),
      text: z.string().max(500).optional(),
      ops: z.array(opSchema).max(8).optional(),
    })
    .strict(),
  z
    .object({
      type: z.literal('decide'),
      requestId: z.string().min(1).max(80),
      proposalId: z.string().min(1).max(120),
      expectedGeneration: z.number().int().nonnegative(),
      decision: z.enum(['apply', 'reject']),
      acceptedOpIds: z.array(z.string().min(1).max(80)).max(8).optional(),
      setEdits: z
        .array(
          z
            .object({
              instanceId: z.string().min(1).max(120),
              sets: z.number().int().min(1).max(6),
            })
            .strict(),
        )
        .max(12)
        .optional(),
    })
    .strict(),
]);

type Dependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  port: CanvasPort;
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

function commandFrom(body: unknown): CanvasCommand | null {
  const parsed = commandSchema.safeParse(body);
  if (!parsed.success) return null;
  const command = parsed.data;
  if (command.type === 'decide') return command;
  if (command.source === 'direct') {
    if (!command.ops || command.text) return null;
    return { ...command, ops: command.ops as CanvasOp[], text: undefined };
  }
  if (!command.text) return null;
  return { ...command, text: command.text, ops: undefined };
}

function statusFor(result: CanvasResult) {
  if (result.kind === 'proposed') {
    return json(
      { proposal: result.proposal, narration: result.narration, replay: result.replay },
      201,
    );
  }
  if (result.kind === 'decided') {
    return json({
      receipt: result.receipt,
      plan: result.plan,
      narration: result.narration,
      replay: result.replay,
    });
  }
  const status =
    result.kind === 'owner_missing' || result.kind === 'proposal_not_found'
      ? 404
      : result.kind === 'stale_context' ||
          result.kind === 'request_conflict' ||
          result.kind === 'already_decided'
        ? 409
        : 400;
  return json(
    {
      error: result.kind,
      ...('missing' in result ? { missing: result.missing } : {}),
      ...('reason' in result ? { reason: result.reason } : {}),
    },
    status,
  );
}

export function createMesocycleCanvasHandlers(deps: Dependencies) {
  async function GET(request: NextRequest) {
    const owner = await deps.authenticate(request);
    if (!owner) return json({ error: 'unauthorized' }, 401);
    if (!deps.enabled()) return json({ error: 'not_found' }, 404);
    const limit = await deps.reserveRequest(owner.sub);
    if (!limit.allowed) {
      return NextResponse.json(
        { version: 1, error: 'rate_limited' },
        {
          status: 429,
          headers: { 'Cache-Control': 'no-store', 'Retry-After': String(limit.retryAfterSeconds) },
        },
      );
    }
    try {
      const journal = await deps.port.read(owner.sub);
      if (!journal) return json({ error: 'owner_missing' }, 404);
      return json({ readback: canvasReadback(journal) });
    } catch {
      return json({ error: 'training_unavailable' }, 503);
    }
  }

  async function POST(request: NextRequest) {
    const owner = await deps.authenticate(request);
    if (!owner) return json({ error: 'unauthorized' }, 401);
    if (!deps.enabled()) return json({ error: 'not_found' }, 404);
    const limit = await deps.reserveRequest(owner.sub);
    if (!limit.allowed) {
      return NextResponse.json(
        { version: 1, error: 'rate_limited' },
        {
          status: 429,
          headers: { 'Cache-Control': 'no-store', 'Retry-After': String(limit.retryAfterSeconds) },
        },
      );
    }
    try {
      const body = await request.json().catch(() => null);
      const command = commandFrom(body);
      if (!command) return json({ error: 'invalid_request' }, 400);
      const result = await reviseCanvas(deps.port, owner.sub, command, deps.now().toISOString());
      return statusFor(result);
    } catch {
      return json({ error: 'training_unavailable' }, 503);
    }
  }

  return { GET, POST };
}
