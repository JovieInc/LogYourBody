import {
  LANDING_AUDIENCES,
  LANDING_GOALS,
  LANDING_GOAL_COPY,
  LANDING_MEDIA,
  LANDING_PRODUCT_PROOF,
  LANDING_RECIPE,
} from './landing-registry';

const BANNED_UNVERIFIED_PROOF = [
  /testimonial/i,
  /app store rating/i,
  /10,?000\+?/i,
  /93%/i,
  /people tracking/i,
  /measurements logged/i,
  /as seen in/i,
];

export interface LandingEvaluationResult {
  score: number;
  passed: boolean;
  hardGates: Record<string, boolean>;
  scores: Record<string, number>;
}

export function evaluateLandingSystem(): LandingEvaluationResult {
  const copyBlob = Object.values(LANDING_GOAL_COPY)
    .flatMap((copy) => Object.values(copy))
    .join('\n');

  const hardGates = {
    noNavigation: LANDING_RECIPE.navigation === 'hidden',
    onePrimaryCta: LANDING_RECIPE.primaryCtaCount === 1,
    honestCopy: BANNED_UNVERIFIED_PROOF.every((pattern) => !pattern.test(copyBlob)),
    realProductCapture:
      LANDING_PRODUCT_PROOF.sourceKind === 'ios-fastlane-capture' &&
      LANDING_PRODUCT_PROOF.truthStatus === 'real-app-capture',
    audienceVariants:
      LANDING_AUDIENCES.length === 2 && LANDING_AUDIENCES.every((id) => Boolean(LANDING_MEDIA[id])),
    goalVariants:
      LANDING_GOALS.length === 3 && LANDING_GOALS.every((id) => Boolean(LANDING_GOAL_COPY[id])),
    pillControls: LANDING_RECIPE.inputShape === 'pill' && LANDING_RECIPE.buttonShape === 'pill',
  };

  const scores = {
    conversionClarity: 30,
    icpResonance: 20,
    honestTrust: hardGates.honestCopy && hardGates.realProductCapture ? 15 : 0,
    mobileUsability: LANDING_RECIPE.mobilePhotoTreatment === 'hidden' ? 15 : 0,
    designSystemFidelity: hardGates.pillControls ? 10 : 0,
    accessibility: 10,
  };
  const score = Object.values(scores).reduce((total, value) => total + value, 0);
  const passed = score >= 90 && Object.values(hardGates).every(Boolean);

  return { score, passed, hardGates, scores };
}
