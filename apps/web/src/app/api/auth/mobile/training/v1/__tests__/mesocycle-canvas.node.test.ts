/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createMesocycleCanvasHandlers } from '../mesocycle-canvas-handlers';
import { createMemoryCanvasPort } from '@/lib/training/mesocycle-canvas';

const now = () => new Date('2026-10-14T12:00:00.000Z');

function request(method = 'GET', body?: unknown) {
  return new NextRequest('http://localhost:3000/api/auth/mobile/training/v1/mesocycle-canvas', {
    method,
    ...(body === undefined
      ? {}
      : { body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } }),
  });
}

function harness() {
  const port = createMemoryCanvasPort();
  const dependencies = {
    port,
    authenticate: jest.fn(async () => ({ sub: 'owner' }) as never),
    reserveRequest: jest.fn(
      async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
    ),
    now,
    enabled: jest.fn(() => true),
  };
  return { port, dependencies, handlers: createMesocycleCanvasHandlers(dependencies) };
}

describe('mesocycle canvas HTTP boundary', () => {
  it('keeps unauthorized and default-off callers away from the journal', async () => {
    const h = harness();
    h.dependencies.authenticate.mockResolvedValueOnce(null as never);
    expect((await h.handlers.GET(request())).status).toBe(401);
    h.dependencies.enabled.mockReturnValueOnce(false);
    expect((await h.handlers.POST(request('POST', { type: 'propose' }))).status).toBe(404);
    expect(await h.port.read('owner')).toEqual({
      version: 1,
      generation: 0,
      applied: [],
      head: -1,
      proposals: [],
    });
  });

  it('returns 503 when the journal store is missing and 409 when a write is stale', async () => {
    const h = harness();
    const failing = {
      ...h.dependencies,
      port: {
        read: jest.fn(async () => {
          throw new Error('function does not exist');
        }),
        write: jest.fn(),
      },
    };
    const down = createMesocycleCanvasHandlers(failing);
    const unavailable = await down.GET(request());
    expect(unavailable.status).toBe(503);
    expect(await unavailable.json()).toEqual({ version: 1, error: 'training_unavailable' });

    const created = await h.handlers.POST(
      request('POST', {
        type: 'propose',
        requestId: 'req-draft',
        expectedGeneration: 0,
        baseRevisionId: null,
        source: 'chat',
        text: 'Build a hypertrophy plan',
        ops: [{ id: 'injected', kind: 'draft' }],
      }),
    );
    expect(created.status).toBe(201);
    const body = await created.json();
    expect(body.proposal.ops).toEqual([{ id: 'draft', kind: 'draft' }]);
    const stale = await h.handlers.POST(
      request('POST', {
        type: 'decide',
        requestId: 'req-stale',
        proposalId: body.proposal.id,
        expectedGeneration: 4,
        decision: 'apply',
      }),
    );
    expect(stale.status).toBe(409);
    expect(await stale.json()).toMatchObject({ error: 'stale_context' });
    expect((await h.port.read('owner'))?.head).toBe(-1);
  });

  it('rejects an unsupported swap before a proposal is stored', async () => {
    const h = harness();
    const draft = await h.handlers.POST(
      request('POST', {
        type: 'propose',
        requestId: 'req-draft',
        expectedGeneration: 0,
        baseRevisionId: null,
        source: 'voice',
        text: 'Build a hypertrophy plan',
      }),
    );
    const proposed = await draft.json();
    await h.handlers.POST(
      request('POST', {
        type: 'decide',
        requestId: 'req-draft-apply',
        proposalId: proposed.proposal.id,
        expectedGeneration: 0,
        decision: 'apply',
      }),
    );
    const swap = await h.handlers.POST(
      request('POST', {
        type: 'propose',
        requestId: 'req-swap',
        expectedGeneration: 1,
        baseRevisionId: (await h.port.read('owner'))?.applied[0]?.id,
        source: 'chat',
        text: 'Swap incline dumbbell press for the Smith machine incline press',
      }),
    );
    expect(swap.status).toBe(400);
    expect(await swap.json()).toMatchObject({
      error: 'unsupported_equipment',
      missing: ['smith_machine'],
    });
    expect((await h.port.read('owner'))?.proposals).toHaveLength(1);
  });
});
