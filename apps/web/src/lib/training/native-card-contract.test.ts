import { readFileSync } from 'node:fs';
import path from 'node:path';
import {
  admitNativeTrainingCardAction,
  NATIVE_TRAINING_CARD_RUNTIME,
  nativeCardsForChatTurn,
  parseNativeTrainingCards,
  type NativeTrainingCard,
} from './native-card-contract';

const owner = 'owner-a';
const proposalId = '33333333-3333-4333-8333-333333333333';
const sessionId = '11111111-1111-4111-8111-111111111111';
const programId = '44444444-4444-4444-8444-444444444444';
const revisionId = '55555555-5555-4555-8555-555555555555';
const resultId = '66666666-6666-4666-8666-666666666666';
const swapId = '77777777-7777-4777-8777-777777777777';
const feedbackId = '88888888-8888-4888-8888-888888888888';
const reviewId = '99999999-9999-4999-8999-999999999999';

function planChange(status: 'pending' | 'applied' | 'rejected' = 'pending'): NativeTrainingCard {
  const cards = nativeCardsForChatTurn({
    proposal: {
      id: proposalId,
      revisionId: null,
      reason: 'Keep the supported cable curl.',
      diff: [{ label: 'Biceps', from: 'Dumbbell curl', to: 'Incline dumbbell curl' }],
      reasons: ['Biceps stay the priority and the bench supports the trunk.'],
      evidenceIds: ['k:81c218db'],
      status,
    },
  });
  const card = cards[0];
  if (!card || card.component !== 'PlanChangeCard') throw new Error('missing plan card');
  return card;
}

function request(card: NativeTrainingCard, action: string, payload: unknown, actor = owner) {
  return {
    schemaVersion: 1,
    action,
    component: card.component,
    object: card.object,
    actorSubject: actor,
    payload,
  };
}

describe('native training card contract', () => {
  it('does not adopt json-render', () => {
    expect(NATIVE_TRAINING_CARD_RUNTIME).toEqual({
      consumer: 'owned-swiftui',
      jsonRender: 'unsupported',
    });
    const source = readFileSync(path.join(__dirname, 'native-card-contract.ts'), 'utf8');
    expect(source).not.toMatch(/from ['"]json-render['"]|require\(['"]json-render['"]\)/);
    const webPackage = readFileSync(path.join(__dirname, '../../../package.json'), 'utf8');
    expect(webPackage).not.toContain('json-render');
  });

  it('rejects unknown components, invalid ids, forbidden fields, and generated code', () => {
    expect(parseNativeTrainingCards({ component: 'WebViewCard' }).ok).toBe(false);
    expect(parseNativeTrainingCards({ component: 'WebViewCard' })).toMatchObject({
      reason: 'unknown_component',
    });
    const card = planChange();
    expect(
      parseNativeTrainingCards({ ...card, object: { ...card.object, id: 'proposal-id' } }),
    ).toMatchObject({ ok: false, reason: 'invalid_id' });
    expect(parseNativeTrainingCards({ ...card, code: 'alert(1)' })).toMatchObject({
      ok: false,
      reason: 'forbidden_field',
    });
    expect(
      parseNativeTrainingCards({ ...card, properties: { ...card.properties, fatigueScore: 9 } }),
    ).toMatchObject({
      ok: false,
      reason: 'forbidden_field',
    });
    expect(parseNativeTrainingCards('eval(global.process)')).toMatchObject({
      ok: false,
      reason: 'generated_code',
    });
    expect(
      parseNativeTrainingCards({
        ...card,
        properties: { ...card.properties, reason: 'Keep it. <script>alert(1)</script>' },
      }),
    ).toMatchObject({ ok: false, reason: 'generated_code' });
  });

  it('admits apply, adjust, and reject only through the saved revision', () => {
    const card = planChange();
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'apply_revision', {}),
      }),
    ).toEqual({
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'decide',
        decision: 'apply',
        proposalId,
      },
    });
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'reject_revision', {}),
      }).ok,
    ).toBe(true);
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'adjust_revision', {
          utterance: 'Prefer the bench-supported curl.',
        }),
      }),
    ).toMatchObject({
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'propose',
        decision: 'adjust',
        baseProposalId: proposalId,
      },
    });
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'apply_revision', {}, 'someone-else'),
      }),
    ).toMatchObject({ ok: false, reason: 'unauthorized' });
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'delete_account', {}),
      }),
    ).toMatchObject({ ok: false, reason: 'unknown_action' });
    expect(
      admitNativeTrainingCardAction({
        card: planChange('applied'),
        ownerSubject: owner,
        request: request(planChange('applied'), 'apply_revision', {}),
      }),
    ).toMatchObject({ ok: false, reason: 'invalid_payload' });
  });

  it('builds a compact plan, a workout, and a swap without a rebuilt plan', () => {
    const cards = nativeCardsForChatTurn({
      program: {
        id: programId,
        revisionId,
        proposalId,
        title: 'Biceps priority',
        weeks: [
          {
            week: 1,
            sessions: [{ id: sessionId, title: 'Upper', slot: 0 }],
          },
        ],
        diff: [{ label: 'Biceps', from: 'Dumbbell curl', to: 'Incline dumbbell curl' }],
        reasons: ['Low trunk demand. The bench supports the torso.'],
        evidenceIds: ['k:81c218db'],
      },
      session: {
        id: sessionId,
        title: 'Upper',
        week: 1,
        slot: 0,
        exercises: [
          {
            id: 'dumbbell_curl',
            name: 'Dumbbell curl',
            sets: 3,
            repRange: { min: 8, max: 12 },
            targetReps: 10,
            targetRir: 2,
            targetLoadKg: 12,
            loadInstruction: 'Elbows stay by the ribs',
          },
        ],
        loggedSets: [
          { exerciseId: 'dumbbell_curl', setNumber: 1, reps: 10, loadKg: 12, rir: 2, revision: 1 },
        ],
      },
      swap: {
        id: swapId,
        sessionId,
        exerciseId: 'dumbbell_curl',
        alternatives: [
          {
            id: 'incline_dumbbell_curl',
            name: 'Incline dumbbell curl',
            tradeoff: 'Bench supports the trunk. Biceps stay the priority.',
          },
          {
            id: 'lying_dumbbell_curl',
            name: 'Lying dumbbell curl',
            tradeoff: 'Floor supports the trunk. Same dumbbells.',
          },
        ],
      },
    });
    expect(cards.map((card) => card.component)).toEqual([
      'MesoPlanCard',
      'WorkoutSessionCard',
      'ExerciseSwapCard',
    ]);
    const plan = cards[0];
    const workout = cards[1];
    const swap = cards[2];
    if (plan?.component !== 'MesoPlanCard' || workout?.component !== 'WorkoutSessionCard') {
      throw new Error('missing cards');
    }
    if (swap?.component !== 'ExerciseSwapCard') throw new Error('missing swap');
    expect(plan.properties.compact).toBe(true);
    expect(plan.properties.weeks).toHaveLength(1);
    expect(plan.properties.diff[0]?.to).toBe('Incline dumbbell curl');
    expect(workout.object.id).toBe(sessionId);
    expect(workout.properties.exercises[0]?.setup).toBe('Elbows stay by the ribs');
    expect(workout.properties.previous[0]?.reps).toBe(10);
    expect(
      admitNativeTrainingCardAction({
        card: swap,
        ownerSubject: owner,
        request: request(swap, 'swap_exercise', {
          toVariantId: 'incline_dumbbell_curl',
          plan: { weeks: [] },
        }),
      }),
    ).toMatchObject({ ok: false, reason: 'unknown_field' });
    expect(
      admitNativeTrainingCardAction({
        card: swap,
        ownerSubject: owner,
        request: request(swap, 'swap_exercise', { toVariantId: 'incline_dumbbell_curl' }),
      }),
    ).toMatchObject({
      ok: true,
      action: {
        operation: 'swap_exercise',
        sessionId,
        exerciseId: 'dumbbell_curl',
        toVariantId: 'incline_dumbbell_curl',
      },
    });
  });

  it('keeps feedback brief and cites recorded results before a review change', () => {
    const cards = nativeCardsForChatTurn({
      feedback: {
        id: feedbackId,
        sessionId,
        prompt: 'Anything sharp or unusual in that set?',
      },
      review: {
        id: reviewId,
        recordedResultIds: [resultId],
        citations: [{ resultId, statement: 'Set 1 was 10 reps at 12 kg, 2 reps in reserve.' }],
        proposedChange: { intent: 'prioritize', evidenceIds: ['k:81c218db'] },
      },
    });
    expect(cards.map((card) => card.component)).toEqual([
      'TrainingFeedbackCard',
      'ProgressReviewCard',
    ]);
    const review = cards[1];
    if (review?.component !== 'ProgressReviewCard') throw new Error('missing review');
    expect(review.properties.proposedChange?.intent).toBe('prioritize');
    expect(
      admitNativeTrainingCardAction({
        card: review,
        ownerSubject: owner,
        request: request(review, 'propose_change', { sets: 12, fatigueScore: 8 }),
      }),
    ).toMatchObject({ ok: false, reason: 'forbidden_field' });
    expect(
      admitNativeTrainingCardAction({
        card: review,
        ownerSubject: owner,
        request: request(review, 'propose_change', {}),
      }),
    ).toMatchObject({
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'propose',
        decision: 'propose_change',
        intent: 'prioritize',
        recordedResultIds: [resultId],
      },
    });
    expect(
      nativeCardsForChatTurn({
        review: {
          id: reviewId,
          recordedResultIds: [],
          citations: [],
          proposedChange: { intent: 'keep', evidenceIds: ['k:81c218db'] },
        },
      }),
    ).toEqual([]);
  });

  it('logs the next set against the session id and rejects a different object', () => {
    const cards = nativeCardsForChatTurn({
      session: {
        id: sessionId,
        title: 'Upper',
        week: 1,
        slot: 0,
        exercises: [
          {
            id: 'dumbbell_curl',
            name: 'Dumbbell curl',
            sets: 2,
            repRange: { min: 8, max: 12 },
            targetReps: 10,
            targetRir: 2,
            targetLoadKg: null,
            loadInstruction: 'Elbows stay by the ribs',
          },
        ],
      },
    });
    const card = cards[0];
    if (card?.component !== 'WorkoutSessionCard') throw new Error('missing workout');
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: request(card, 'log_set', {
          exerciseId: 'dumbbell_curl',
          setNumber: 1,
          reps: 10,
          loadKg: null,
          rir: 2,
        }),
      }),
    ).toMatchObject({ ok: true, action: { operation: 'log_set', sessionId, setNumber: 1 } });
    expect(
      admitNativeTrainingCardAction({
        card,
        ownerSubject: owner,
        request: {
          ...request(card, 'log_set', {
            exerciseId: 'dumbbell_curl',
            setNumber: 1,
            reps: 10,
            loadKg: null,
            rir: 2,
          }),
          object: { ...card.object, id: proposalId },
        },
      }),
    ).toMatchObject({ ok: false, reason: 'object_mismatch' });
  });
});
