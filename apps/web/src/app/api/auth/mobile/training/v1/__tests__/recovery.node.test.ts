/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createRecoveryRouteHandlers } from '../recovery-route-handlers';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { storeProgramSetup } from '@/lib/training/service';

const timestamp = new Date('2026-10-12T12:00:00.000Z');
const target = { muscle: 'shoulders', exerciseId: 'dumbbell_lateral_raise', goal: 'emphasize' };
const trialId = '11111111-1111-4111-8111-000000000009';
const setupId = '11111111-1111-4111-8111-000000000001';
function request(method: string, body?: unknown) {
  return new NextRequest(
    'http://localhost:3000/api/auth/mobile/training/v1/recovery-trials?' +
      new URLSearchParams(target),
    {
      method,
      ...(body ? { body: JSON.stringify(body) } : {}),
    },
  );
}
async function fixture() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject: 'owner',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      equipment: 'dumbbells',
      sessionsPerWeek: 3,
    },
    now: timestamp,
    createId: () => setupId,
  });
  const dependencies = {
    records,
    authenticate: jest.fn(async () => ({ sub: 'owner' }) as never),
    reserveRequest: jest.fn(
      async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
    ),
    enabled: jest.fn(() => true),
    now: () => timestamp,
  };
  return { records, dependencies, handlers: createRecoveryRouteHandlers(dependencies) };
}
describe('adaptive recovery HTTP boundary', () => {
  it('requires identity, rollout admission and rate allowance before reading training data', async () => {
    const h = await fixture();
    const pull = jest.spyOn(h.records, 'pull');
    h.dependencies.authenticate.mockResolvedValueOnce(null as never);
    expect((await h.handlers.GET(request('GET'))).status).toBe(401);
    h.dependencies.enabled.mockReturnValueOnce(false);
    expect((await h.handlers.GET(request('GET'))).status).toBe(404);
    h.dependencies.reserveRequest.mockResolvedValueOnce({
      allowed: false,
      retryAfterSeconds: 30,
    } as never);
    const limited = await h.handlers.GET(request('GET'));
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).toBe('30');
    expect(pull).not.toHaveBeenCalled();
  });
  it('evaluates without writes, persists a proposal, rejects it and replays its history', async () => {
    const h = await fixture();
    const before = await h.records.listAll('owner');
    const read = await h.handlers.GET(request('GET'));
    expect(await read.json()).toMatchObject({
      evaluation: { action: 'insufficient_evidence' },
      trials: [],
    });
    expect(read.headers.get('Cache-Control')).toBe('no-store');
    expect(await h.records.listAll('owner')).toEqual(before);
    const created = await h.handlers.POST(request('POST', { ...target, requestId: trialId }));
    expect(created.status).toBe(201);
    expect(await created.json()).toMatchObject({
      trial: { state: 'proposed', version: 1, revision: 0 },
    });
    const noChange = await h.handlers.PATCH(
      request('PATCH', { trialId, expectedRevision: 0, decision: 'apply' }),
    );
    expect(noChange.status).toBe(409);
    const rejected = await h.handlers.PATCH(
      request('PATCH', { trialId, expectedRevision: 0, decision: 'reject' }),
    );
    expect(await rejected.json()).toMatchObject({ trial: { state: 'rejected', revision: 1 } });
    const replay = await h.handlers.GET(request('GET'));
    expect(await replay.json()).toMatchObject({
      trials: [{ state: 'rejected', history: [{ state: 'proposed' }, { state: 'rejected' }] }],
    });
  });
  it('rejects invented policy values and fails closed without atomic storage', async () => {
    const h = await fixture();
    const invalid = await h.handlers.POST(
      request('POST', { ...target, requestId: trialId, setCap: 40 }),
    );
    expect(invalid.status).toBe(400);
    h.records.trainingMutations.commitRecoveryTrial = undefined;
    expect((await h.handlers.POST(request('POST', { ...target, requestId: trialId }))).status).toBe(
      503,
    );
    h.dependencies.authenticate.mockResolvedValueOnce({ sub: 'other-owner' } as never);
    expect(
      (
        await h.handlers.PATCH(
          request('PATCH', { trialId, expectedRevision: 0, decision: 'apply' }),
        )
      ).status,
    ).toBe(409);
  });
});
