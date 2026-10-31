/** @jest-environment node */

import { makeHarness, request, eligibleSetup } from '../route-harness.testing';

describe('authenticated exercise selection API', () => {
  it('protects the selection review with authentication, both rollouts and rate limits before reading records', async () => {
    for (const [options, token, status] of [
      [{}, undefined, 401],
      [{ enabled: false }, 'token-a', 404],
      [{ selectionEnabled: false }, 'token-a', 404],
      [{ rateLimited: true }, 'token-a', 429],
    ] as const) {
      const { handlers, records } = makeHarness(options);
      const pull = jest.spyOn(records, 'pull');
      const response = await handlers.alternatives(request('POST', 'alternatives', token, {}));
      expect(response.status).toBe(status);
      expect(response.headers.get('cache-control')).toBe('no-store');
      expect(pull).not.toHaveBeenCalled();
    }
  });

  it('reviews native selection, rejects cross-owner access and keeps proposals read-only', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(
      request('POST', 'enroll', 'token-a', {
        ...eligibleSetup,
        equipment: 'full_gym',
        sessionsPerWeek: 5,
      }),
    );
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const row = (await records.pull('subject-a', 'training_sessions')).records.find(
      (item) => item.id === session.id,
    )!;
    const curl = {
      ...session.exercises[0],
      id: 'cable_curl',
      name: 'Cable curl',
      primaryMuscle: 'biceps',
      muscleContribution: { biceps: 1 },
    };
    await records.push('subject-a', 'training_sessions', [
      { ...row, prescription: { ...session, exercises: [curl] } },
    ]);
    const feedback = await handlers.feedback(
      request('POST', 'feedback', 'token-a', {
        sessionId: session.id,
        context: { exerciseId: curl.id, setNumber: 1, gymId: 'Gym', romRestriction: 'limited' },
        trunkFatigue: 6,
        generalExhaustion: 1,
        targetMuscleQuality: 'good',
        stability: 'stable',
      }),
    );
    expect(feedback.status).toBe(201);
    const feedbackBody = await feedback.json();
    expect(feedbackBody.feedback.jointPain).toBeUndefined();
    expect(feedbackBody.feedback.generalExhaustion).toBe(1);
    const body = {
      sessionId: session.id,
      exerciseId: curl.id,
      context: {
        gymId: 'Gym',
        availableEquipment: ['cable', 'adjustable_bench', 'machine'],
        excludedConcerns: [],
      },
    };
    const push = jest.spyOn(records, 'push');
    const commit = jest.spyOn(records.trainingMutations, 'commit');
    const response = await handlers.alternatives(request('POST', 'alternatives', 'token-a', body));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const { review } = await response.json();
    expect(review.options).toHaveLength(2);
    expect(review.options[1]).toMatchObject({
      variantId: 'supported_cable_curl',
      setup: { variantMetadata: { romSetupCaveat: expect.any(String) } },
    });
    expect(push).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
    expect(
      (await handlers.alternatives(request('POST', 'alternatives', 'token-b', body))).status,
    ).toBe(404);
    expect(
      (
        await handlers.alternatives(
          request('POST', 'alternatives', 'token-a', {
            ...body,
            context: { ...body.context, availableEquipment: ['imaginary_station'] },
          }),
        )
      ).status,
    ).toBe(400);
  });
});
