import type { TrainingFeedback } from './types';

export const CONCERNING_PAIN_MESSAGE =
  'Stop this movement. If pain is persistent, worsening, or includes numbness, weakness, or other neurologic symptoms, seek evaluation from a qualified clinician.';

export type MovementPainFeedback = Pick<
  TrainingFeedback,
  'jointPain' | 'trunkFatigue' | 'symptomFlags'
> & {
  /** Explicit reports, never inferred from a score, fatigue or elapsed time. */
  persistentPain?: boolean;
  worseningPain?: boolean;
};

export type MovementPainDecision =
  | {
      action: 'pause_movement';
      swapAllowed: false;
      coachingAllowed: false;
      explanation: typeof CONCERNING_PAIN_MESSAGE;
    }
  | { action: 'continue_to_swap'; swapAllowed: true; explanation: null };

/** Movement-scoped policy only. Continuing to swap still requires the existing
 * symptom, session, equipment and eligibility checks; it is not medical clearance.
 */
export function evaluateMovementPain(feedback?: MovementPainFeedback): MovementPainDecision {
  if (
    feedback?.persistentPain === true ||
    feedback?.worseningPain === true ||
    feedback?.symptomFlags?.includes('neurologic')
  ) {
    return {
      action: 'pause_movement',
      swapAllowed: false,
      coachingAllowed: false,
      explanation: CONCERNING_PAIN_MESSAGE,
    };
  }
  return { action: 'continue_to_swap', swapAllowed: true, explanation: null };
}
