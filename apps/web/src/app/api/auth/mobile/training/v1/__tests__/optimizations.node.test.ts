/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createTrainingOptimizerHandlers } from '../optimizer-route-handlers';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from '@/lib/training/service';
import { logTrainingSet } from '@/lib/training/commands';

const body = {
  sessions: [
    {
      id: 'solo',
      day: 'monday',
      part: 'any',
      exercises: [{ id: 'goblet_squat', name: 'Goblet squat', primaryMuscle: 'quads', sets: 2 }],
    },
  ],
  equipmentProfile: 'dumbbells',
  locationId: null,
  locationPermission: 'unknown',
  stationGeography: 'unknown',
};

function request(method: string, payload?: unknown) {
  return new NextRequest('http://localhost:3000/api/auth/mobile/training/v1/optimizations', {
    method,
    ...(payload === undefined
      ? {}
      : { body: JSON.stringify(payload), headers: { 'Content-Type': 'application/json' } }),
  });
}

function handlers(overrides: { coach?: boolean; optimizer?: boolean } = {}) {
  return createTrainingOptimizerHandlers({
    authenticate: jest.fn(async () => ({ sub: 'owner' }) as never),
    reserveRequest: jest.fn(
      async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
    ),
    coachEnabled: () => overrides.coach !== false,
    optimizerEnabled: () => overrides.optimizer === true,
  });
}

describe('mesocycle optimizer HTTP boundary', () => {
  async function rollingHarness() {
    const records = new MemoryTrainingRecords();
    await storeProgramSetup({
      records,
      subject: 'owner',
      now: new Date('2026-10-20T08:00:00Z'),
      createId: () => '11111111-1111-4111-8111-111111111111',
      setup: {
        adultConfirmed: true,
        safetyConfirmed: true,
        sessionsPerWeek: 2,
        equipment: 'dumbbells',
      },
    });
    const open = createTrainingOptimizerHandlers({
      authenticate: async () => ({ sub: 'owner' }) as never,
      reserveRequest: async () =>
        ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
      coachEnabled: () => true,
      optimizerEnabled: () => true,
      records,
    });
    const source = {
      ...body,
      rollingSchedule: {
        programSetupId: 'claimed-setup',
        blockId: 'claimed-block',
        rotationId: 'claimed-rotation',
        asOf: '2026-10-26T08:00:00Z',
        attendanceSince: '2020-01-01T00:00:00Z',
        requestedVisitsPerWeek: 6,
        slots: [
          {
            id: 'offered',
            scheduledAt: '2026-10-26T20:00:00Z',
            timeZone: 'UTC',
            locationId: 'gym',
            groupId: 'offered',
            visitId: 'offered',
            kind: 'visit',
            availableEquipment: ['dumbbells', 'bench'],
            priorityTargets: [],
          },
        ],
        history: [],
        observations: [],
        trials: [],
        timing: { warmUpSeconds: 300, setSeconds: 60, restSeconds: 120, transitionSeconds: 60 },
      },
    };
    return { records, open, source };
  }

  it('rebuilds rolling proposals from owned approved work, detects new logs at acceptance, and never writes a plan', async () => {
    const { records, open, source } = await rollingHarness();
    const workout = await getOrCreateNextWorkout({
      records,
      subject: 'owner',
      now: new Date('2026-10-25T08:00:00Z'),
    });
    if (workout.kind !== 'workout') throw new Error('Expected workout');
    const before = await records.listAll('owner');
    const createdResponse = await open.POST(request('POST', source));
    expect(createdResponse.status).toBe(200);
    const created = await createdResponse.json();
    expect(created.proposal.rollingSchedule.allocations[0].work.length).toBeGreaterThan(2);
    expect(
      created.proposal.rollingSchedule.allocations[0].work.map(
        (set: { exerciseId: string }) => set.exerciseId,
      ),
    ).toContain('dumbbell_lateral_raise');
    const decide = () =>
      open.PATCH(
        request('PATCH', {
          source,
          proposal: created.proposal,
          decision: 'apply',
          currentFingerprint: created.proposal.baseFingerprint,
        }),
      );
    const accepted = await decide();
    expect(accepted.status).toBe(200);
    expect(await accepted.json()).toMatchObject({
      persisted: false,
      rollingSchedule: expect.any(Object),
      receipt: { writesPerformed: false, enrollment: false },
    });
    expect(await records.listAll('owner')).toEqual(before);
    expect(
      await logTrainingSet({
        records,
        subject: 'owner',
        now: new Date('2026-10-25T09:00:00Z'),
        set: {
          sessionId: workout.session.id,
          exerciseId: workout.session.exercises[0]!.id,
          setNumber: 1,
          reps: 10,
          loadKg: 10,
          rir: 3,
        },
      }),
    ).toMatchObject({ kind: 'logged' });
    const stale = await decide();
    expect(stale.status).toBe(409);
    expect(await stale.json()).toMatchObject({ error: 'not_certified' });
    const refreshed = await (await open.POST(request('POST', source))).json();
    expect(refreshed.proposal.rollingSchedule.completedSetIds).toHaveLength(1);
    expect(refreshed.proposal.rollingSchedule.trailingVolume.days7.quads).toBe(1);
  });

  it("fails closed if owned evidence is unavailable and keeps another owner's work out of the receipt", async () => {
    const { records, open, source } = await rollingHarness();
    const closed = handlers({ optimizer: true });
    expect((await closed.POST(request('POST', source))).status).toBe(503);
    const before = await (await open.POST(request('POST', source))).json();
    await records.push('other-owner', 'logged_sets', [
      {
        id: 'foreign',
        record_type: 'set_log',
        sessionId: 'foreign-session',
        exerciseId: 'goblet_squat',
        setNumber: 1,
        reps: 10,
        loadKg: 10,
        rir: 2,
        completedAt: '2026-10-25T09:00:00Z',
      },
    ]);
    const after = await (await open.POST(request('POST', source))).json();
    expect(after).toEqual(before);
  });
  it('rejects malformed nested proposals instead of trusting their claimed certification', async () => {
    const open = handlers({ optimizer: true });
    const created = await (await open.POST(request('POST', body))).json();
    for (const malformed of [
      null,
      [],
      { ...created.proposal, changes: [null] },
      { ...created.proposal, findings: null },
      { ...created.proposal, tradeoff: {} },
    ]) {
      const response = await open.PATCH(
        request('PATCH', {
          source: body,
          proposal: malformed,
          decision: 'apply',
          currentFingerprint: created.proposal.baseFingerprint,
        }),
      );
      expect([400, 409]).toContain(response.status);
    }
  });
  it('stays hidden unless both the coach API and the optimizer flag are on', async () => {
    const closed = handlers({ optimizer: false });
    expect((await closed.POST(request('POST', body))).status).toBe(404);
    const coachOff = handlers({ coach: false, optimizer: true });
    expect((await coachOff.POST(request('POST', body))).status).toBe(404);
    const anonymous = createTrainingOptimizerHandlers({
      authenticate: jest.fn(async () => null),
      reserveRequest: jest.fn(),
      coachEnabled: () => true,
      optimizerEnabled: () => true,
    });
    expect((await anonymous.POST(request('POST', body))).status).toBe(401);
  });

  it('returns a reviewable proposal and an acceptance that does not write', async () => {
    const open = handlers({ optimizer: true });
    const created = await open.POST(request('POST', body));
    expect(created.status).toBe(200);
    const payload = await created.json();
    expect(payload.persisted).toBe(false);
    expect(payload.proposal.status).toBe('proposed');
    expect(payload.proposal.authority).toBe('self_review_required');
    const decided = await open.PATCH(
      request('PATCH', {
        source: body,
        proposal: payload.proposal,
        decision: 'apply',
        currentFingerprint: payload.proposal.baseFingerprint,
      }),
    );
    expect(decided.status).toBe(200);
    const receipt = await decided.json();
    expect(receipt.persisted).toBe(false);
    expect(receipt.receipt.writesPerformed).toBe(false);
    expect(receipt.receipt.enrollment).toBe(false);
    expect(receipt.receipt.status).toBe('accepted');
  });
});
