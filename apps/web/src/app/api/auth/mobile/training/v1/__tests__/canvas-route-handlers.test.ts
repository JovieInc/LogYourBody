/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createCanvasRouteHandlers } from '../canvas-route-handlers';
import { memoryCanvasPort, readCanvas } from '@/lib/training/mesocycle-canvas';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';

function handlers(overrides: Partial<Parameters<typeof createCanvasRouteHandlers>[0]> = {}) {
  const ledger = memoryCanvasPort();
  const route = createCanvasRouteHandlers({
    authenticate: async (request) =>
      request.headers.get('authorization')?.match(/^Bearer\s+\S+$/i)
        ? ({ sub: 'owner' } as never)
        : null,
    accounts: {
      capture: async (subject) => ({ subject, ownerId: '11111111-1111-4111-8111-111111111111' }),
    },
    ledgerForAccount: () => ledger,
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
  it('replays the native command identity after a lost apply response and rejects changed reuse', async () => {
    const { route } = handlers();
    const draft = {
      action: 'submit',
      requestId: '11111111-1111-4111-8111-111111111111',
      transcript: 'Build a 4-week hypertrophy plan for a full gym',
      expectedWrite: null,
    };
    const proposed = await (await route.POST(post(draft))).json();
    const command = {
      action: 'decide',
      requestId: '22222222-2222-4222-8222-222222222222',
      proposalId: proposed.proposal.id,
      decision: 'apply',
      expectedWrite: proposed.readback.write,
    };
    const saved = await (await route.POST(post(command))).json();
    const retry = await route.POST(post(command));
    expect(retry.status).toBe(200);
    const replay = await retry.json();
    expect(replay.receipt).toEqual(saved.receipt);
    expect(replay.readback.plan).toEqual(saved.readback.plan);
    const changed = await route.POST(post({ ...command, decision: 'reject' }));
    expect(changed.status).toBe(409);
    expect(await changed.json()).toMatchObject({ kind: 'request_conflict' });
    const order = await route.POST(
      post({
        action: 'submit',
        requestId: '33333333-3333-4333-8333-333333333333',
        transcript: 'Put side delts first',
        expectedWrite: saved.readback.write,
      }),
    );
    expect(order.status).toBe(200);
    const preview = await order.json();
    expect(preview).toMatchObject({ kind: 'proposed', applied: false });
    expect(preview.readback.plan).toEqual(saved.readback.plan);
    const read = await (await route.POST(post({ action: 'read' }))).json();
    expect(read.readback.plan).toEqual(saved.readback.plan);
  });

  it('rate limits and validates command identity before a proposal can write', async () => {
    const reserveRequest = jest.fn(async () => ({
      allowed: false as const,
      retryAfterSeconds: 15,
    }));
    const limited = handlers({ reserveRequest });
    const response = await limited.route.POST(
      post({ action: 'submit', transcript: 'Put biceps first', expectedWrite: null }),
    );
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('15');
    expect((await readCanvas(limited.ledger, 'owner')).readback.write).toBeNull();
    const { route, ledger } = handlers();
    const invalid = await route.POST(
      post({
        action: 'submit',
        transcript: 'Put biceps first',
        expectedWrite: null,
        requestId: 'not-a-uuid',
      }),
    );
    expect(invalid.status).toBe(400);
    expect((await readCanvas(ledger, 'owner')).readback.write).toBeNull();
  });
  it.each([
    [null, 404, 'account_not_found'],
    [new NativeAccountAdmissionError('account_changed'), 409, 'account_changed'],
    [
      new NativeAccountAdmissionError('account_admission_unavailable'),
      503,
      'account_admission_unavailable',
    ],
  ] as const)('fails closed when account admission is %s', async (failure, status, error) => {
    const capture = jest.fn(async () => {
      if (failure) throw failure;
      return null;
    });
    const reserveRequest = jest.fn();
    const ledgerForAccount = jest.fn();
    const { route } = handlers({ accounts: { capture }, reserveRequest, ledgerForAccount });
    const request = post({ action: 'read' });
    const read = jest.spyOn(request, 'json');
    const response = await route.POST(request);
    expect(response.status).toBe(status);
    expect(await response.json()).toMatchObject({ error });
    expect(capture).toHaveBeenCalledTimes(1);
    expect(reserveRequest).not.toHaveBeenCalled();
    expect(ledgerForAccount).not.toHaveBeenCalled();
    expect(read).not.toHaveBeenCalled();
  });

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
