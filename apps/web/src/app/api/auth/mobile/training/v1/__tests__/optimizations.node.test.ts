/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createTrainingOptimizerHandlers } from '../optimizer-route-handlers';

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
