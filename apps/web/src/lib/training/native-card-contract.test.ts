import {
  NATIVE_TRAINING_CARD_RENDER_TARGET,
  adjustmentUtteranceIsValid,
  approveTranscriptCard,
  savedRevisionDecision,
  validateNativeTrainingCard,
} from './native-card-contract';

const owner = 'user-subject-1';
const sessionId = '11111111-1111-4111-8111-111111111111';
const proposalId = '22222222-2222-4222-8222-222222222222';
const exerciseId = '33333333-3333-4333-8333-333333333333';
const variantId = '44444444-4444-4444-8444-444444444444';

function planChange(extra: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    component: 'PlanChangeCard',
    objectId: proposalId,
    revision: '7',
    ownerSubject: owner,
    props: {
      proposalId,
      status: 'proposed',
      summary: ['Biceps priority stays for this block'],
      reasons: ['Engine kept the low-trunk movements'],
    },
    actions: [
      {
        kind: 'apply_saved_revision',
        operation: 'saved_revision',
        proposalId,
        expectedRevision: '7',
      },
    ],
    ...extra,
  };
}

function workoutCard() {
  return {
    schemaVersion: 1,
    component: 'WorkoutSessionCard',
    objectId: sessionId,
    revision: '3',
    ownerSubject: owner,
    props: {
      sessionId,
      title: 'Upper A',
      exercises: [{ id: exerciseId, name: 'Incline curl' }],
    },
    actions: [
      { kind: 'open_session', operation: 'read' },
      {
        kind: 'log_set',
        operation: 'session_log',
        sessionId,
        exerciseId,
        setNumber: 1,
      },
    ],
  };
}

describe('native training card contract', () => {
  it('does not treat json-render as a SwiftUI consumer', () => {
    expect(NATIVE_TRAINING_CARD_RENDER_TARGET.jsonRenderSupported).toBe(false);
    expect(NATIVE_TRAINING_CARD_RENDER_TARGET.consumer).toBe('swiftui-owned-views');
  });

  it('approves a saved-revision apply that matches the durable proposal', () => {
    const validated = validateNativeTrainingCard(planChange(), owner);
    expect(validated.ok).toBe(true);
    if (!validated.ok) return;
    expect(validated.card.actions[0]?.operation).toBe('saved_revision');
    expect(savedRevisionDecision('apply_saved_revision')).toBe('apply');
    expect(savedRevisionDecision('adjust_saved_revision')).toBe('adjust');
    expect(savedRevisionDecision('reject_saved_revision')).toBe('reject');
    expect(savedRevisionDecision('run_code')).toBeNull();
    expect(adjustmentUtteranceIsValid('Keep the biceps priority and shorten the session.')).toBe(
      true,
    );
    expect(adjustmentUtteranceIsValid('javascript:alert(1)')).toBe(false);
    const transcript = approveTranscriptCard(planChange(), owner, [validated.card]);
    expect(transcript.ok).toBe(true);
  });

  it('rejects unknown components, invalid ids, unauthorized writes, and generated code', () => {
    expect(validateNativeTrainingCard(planChange({ component: 'WebWorkoutApp' }), owner).ok).toBe(
      false,
    );
    expect(
      validateNativeTrainingCard(planChange({ objectId: 'transcript-9' }), owner),
    ).toMatchObject({
      ok: false,
      reason: 'invalid_id',
    });
    expect(validateNativeTrainingCard(planChange(), 'someone-else')).toMatchObject({
      ok: false,
      reason: 'unauthorized',
    });
    expect(
      validateNativeTrainingCard(planChange({ code: 'process.exit(1)' }), owner),
    ).toMatchObject({ ok: false, reason: 'generated_code' });
    expect(
      validateNativeTrainingCard(
        planChange({ props: { proposalId, note: 'javascript:alert(1)' } }),
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'generated_code' });
    expect(
      validateNativeTrainingCard(
        {
          schemaVersion: 1,
          component: 'Card',
          root: 'main',
          elements: { main: { type: 'Card', props: {} } },
          objectId: proposalId,
          revision: '7',
          ownerSubject: owner,
          props: {},
          actions: [],
        },
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'generated_code' });
  });

  it('rejects transcript-only cards and actions the durable card did not approve', () => {
    const durable = validateNativeTrainingCard(planChange({ actions: [] }), owner);
    expect(durable.ok).toBe(true);
    if (!durable.ok) return;
    const inventedId = '99999999-9999-4999-8999-999999999999';
    const invented = planChange({
      objectId: inventedId,
      props: { proposalId: inventedId },
      actions: [
        {
          kind: 'apply_saved_revision',
          operation: 'saved_revision',
          proposalId: inventedId,
          expectedRevision: '7',
        },
      ],
    });
    expect(approveTranscriptCard(invented, owner, [durable.card])).toMatchObject({
      ok: false,
      reason: 'transcript_only',
    });
    expect(approveTranscriptCard(planChange(), owner, [durable.card])).toMatchObject({
      ok: false,
      reason: 'unauthorized',
    });
  });

  it('keeps swaps inside eligible alternatives and review proposals tied to recorded results', () => {
    const swap = {
      schemaVersion: 1,
      component: 'ExerciseSwapCard',
      objectId: sessionId,
      revision: '3',
      ownerSubject: owner,
      props: {
        sessionId,
        exerciseId,
        alternatives: [
          { id: variantId, name: 'Bayesian curl', tradeoffs: ['biceps contribution: 0.7 -> 0.9'] },
        ],
      },
      actions: [
        {
          kind: 'select_swap',
          operation: 'exercise_swap',
          sessionId,
          toVariantId: 'not-on-the-card',
        },
      ],
    };
    expect(validateNativeTrainingCard(swap, owner)).toMatchObject({
      ok: false,
      reason: 'invalid_id',
    });
    swap.actions[0].toVariantId = variantId;
    expect(validateNativeTrainingCard(swap, owner).ok).toBe(true);

    expect(
      validateNativeTrainingCard(
        {
          schemaVersion: 1,
          component: 'ProgressReviewCard',
          objectId: sessionId,
          revision: '3',
          ownerSubject: owner,
          props: {
            citedResultIds: [],
            proposal: { before: '4 sets', after: '5 sets', rationale: 'engine' },
          },
          actions: [{ kind: 'refresh' }],
        },
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'invalid_schema' });
    expect(
      validateNativeTrainingCard(
        {
          schemaVersion: 1,
          component: 'ProgressReviewCard',
          objectId: sessionId,
          revision: '3',
          ownerSubject: owner,
          props: { citedResultIds: [sessionId], readinessScore: 88 },
          actions: [],
        },
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'invented_score' });
  });

  it('accepts a workout log bound to the session and rejects a foreign session write', () => {
    expect(validateNativeTrainingCard(workoutCard(), owner).ok).toBe(true);
    const foreign = workoutCard();
    foreign.actions[1] = {
      kind: 'log_set',
      operation: 'session_log',
      sessionId: proposalId,
      exerciseId,
      setNumber: 1,
    };
    expect(validateNativeTrainingCard(foreign, owner)).toMatchObject({
      ok: false,
      reason: 'unauthorized',
    });
    expect(
      validateNativeTrainingCard(
        {
          ...workoutCard(),
          actions: [
            {
              kind: 'log_set',
              operation: 'session_log',
              sessionId,
              exerciseId,
              setNumber: 0,
            },
          ],
        },
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'invalid_schema' });
    expect(
      validateNativeTrainingCard(
        {
          ...workoutCard(),
          actions: [
            {
              kind: 'log_set',
              operation: 'session_log',
              sessionId,
              exerciseId,
              setNumber: 1,
              code: 'process.exit(1)',
            },
          ],
        },
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'generated_code' });
    expect(
      validateNativeTrainingCard(
        planChange({ actions: [{ kind: 'run_code', operation: 'saved_revision' }] }),
        owner,
      ),
    ).toMatchObject({ ok: false, reason: 'unsupported_action' });
  });
});
