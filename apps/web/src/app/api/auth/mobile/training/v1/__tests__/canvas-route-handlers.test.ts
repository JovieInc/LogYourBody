/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createCanvasRouteHandlers } from '../canvas-route-handlers';
import { memoryCanvasPort, readCanvas } from '@/lib/training/mesocycle-canvas';

function handlers(overrides: Partial<Parameters<typeof createCanvasRouteHandlers>[0]> = {}) {
  const ledger = memoryCanvasPort();
  const route = createCanvasRouteHandlers({
    authenticate: async (request) =>
      request.headers.get('authorization')?.match(/^Bearer\s+\S+$/i)
        ? ({ sub: 'owner' } as never)
        : null,
    ledger,
    reserveRequest: async () => ({ allowed: true, remainingInWindow: 10, remainingToday: 10 }),
    now: () => new Date('2026-10-14T18:00:00.000Z'),
    enabled: () => true,
    ...overrides,
  });
  return { route, ledger };
}

function post(body: unknown, authorization = 'Bearer token') {
  return new NextRequest('http://localhost/api/auth/mobile/training/v1/canvas', {
    method: 'POST',
    headers: {
      authorization,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

describe('mesocycle canvas route', () => {
  it('hides the route until the caller is signed in and the flag is on', async () => {
    const disabled = handlers({ enabled: () => false });
    const hidden = await disabled.route.POST(post({ action: 'read' }));
    expect(hidden.status).toBe(404);

    const { route } = handlers();
    const anonymous = await route.POST(post({ action: 'read' }, ''));
    expect(anonymous.status).toBe(401);
  });

  it('proposes a chat edit without applying it, then accepts it once', async () => {
    const { route, ledger } = handlers();
    const proposed = await route.POST(
      post({
        action: 'submit',
        transcript: 'Build a 4-week hypertrophy plan for a full gym',
        expectedWrite: null,
      }),
    );
    expect(proposed.status).toBe(200);
    const proposal = (await proposed.json()) as {
      kind: string;
      applied: boolean;
      proposal: { id: string };
      readback: { write: number; plan: unknown };
    };
    expect(proposal).toMatchObject({ kind: 'proposed', applied: false, readback: { plan: null } });
    expect((await readCanvas(ledger, 'owner')).readback.plan).toBeNull();

    const accepted = await route.POST(
      post({
        action: 'decide',
        proposalId: proposal.proposal.id,
        decision: 'apply',
        expectedWrite: proposal.readback.write,
      }),
    );
    expect(accepted.status).toBe(200);
    const saved = (await accepted.json()) as {
      kind: string;
      readback: { plan: { revision: number }; write: number };
    };
    expect(saved.kind).toBe('decided');
    expect(saved.readback.plan.revision).toBe(1);

    const duplicate = await route.POST(
      post({
        action: 'decide',
        proposalId: proposal.proposal.id,
        decision: 'apply',
        expectedWrite: saved.readback.write,
      }),
    );
    expect(duplicate.status).toBe(409);
    const replay = (await duplicate.json()) as {
      kind: string;
      readback: { plan: { revision: number } };
    };
    expect(replay.kind).toBe('already_decided');
    expect(replay.readback.plan.revision).toBe(1);
  });

  it('rejects unsupported equipment without writing a plan change', async () => {
    const { route, ledger } = handlers();
    const proposed = await route.POST(
      post({
        action: 'submit',
        transcript: 'Build a 4-week hypertrophy plan for a full gym',
        expectedWrite: null,
      }),
    );
    const proposal = (await proposed.json()) as {
      proposal: { id: string };
      readback: { write: number };
    };
    const accepted = await route.POST(
      post({
        action: 'decide',
        proposalId: proposal.proposal.id,
        decision: 'apply',
        expectedWrite: proposal.readback.write,
      }),
    );
    const saved = (await accepted.json()) as { readback: { write: number; plan: unknown } };
    const before = saved.readback.plan;

    const blocked = await route.POST(
      post({
        action: 'propose',
        expectedWrite: saved.readback.write,
        operation: {
          kind: 'swap',
          exerciseName: 'Incline dumbbell press',
          toVariantId: 'smith_incline_press',
          declareEquipment: [],
        },
      }),
    );
    expect(blocked.status).toBe(409);
    const body = (await blocked.json()) as { kind: string; missing?: string[] };
    expect(body.kind).toBe('unsupported_equipment');
    expect(body.missing).toContain('smith');
    expect((await readCanvas(ledger, 'owner')).readback.plan).toEqual(before);
  });
});
