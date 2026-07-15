import productAssets from '@/generated/marketing-product-assets.json';

export const LANDING_AUDIENCES = ['men', 'women'] as const;
export const LANDING_GOALS = ['recomposition', 'fat-loss', 'muscle-gain'] as const;

export type LandingAudience = (typeof LANDING_AUDIENCES)[number];
export type LandingGoal = (typeof LANDING_GOALS)[number];
export type LandingAssignmentSource = 'experiment' | 'campaign' | 'returning';

export interface LandingVariantRequest {
  audience?: string | null;
  goal?: string | null;
}

export interface LandingVariant {
  audience: LandingAudience;
  goal: LandingGoal;
  heroImage: string;
  heroAlt: string;
  headline: string;
  subheading: string;
  framingLine: string;
}

export const LANDING_RECIPE = {
  id: 'waitlist-editorial-product-proof',
  sectionOrder: ['hero', 'capture', 'product-proof', 'closing-line'],
  navigation: 'hidden',
  primaryCtaCount: 1,
  inputShape: 'pill',
  buttonShape: 'pill',
  mobilePhotoTreatment: 'hidden',
  desktopPhotoTreatment: 'full-bleed-right',
} as const;

export const LANDING_MEDIA: Record<
  LandingAudience,
  { src: string; alt: string; width: number; height: number }
> = {
  men: {
    src: '/marketing/landing/hero-men-v1.png',
    alt: 'Athlete in a private performance studio after training',
    width: 1536,
    height: 1024,
  },
  women: {
    src: '/marketing/landing/hero-women-v1.png',
    alt: 'Woman athlete in a private performance studio after training',
    width: 1536,
    height: 1024,
  },
};

export const LANDING_GOAL_COPY: Record<
  LandingGoal,
  Pick<LandingVariant, 'headline' | 'subheading' | 'framingLine'>
> = {
  recomposition: {
    headline: 'Know if the work is working.',
    subheading:
      'Weight, body fat, lean mass, and progress photos—one private timeline that shows the trend.',
    framingLine: 'One timeline. The signal, without the noise.',
  },
  'fat-loss': {
    headline: 'Know if the cut is working.',
    subheading:
      'See weight, body fat, lean mass, and progress photos together—so a lower number never hides the real trend.',
    framingLine: 'Lose fat. Keep the signal that matters.',
  },
  'muscle-gain': {
    headline: 'Know what the gain is building.',
    subheading:
      'See weight, lean mass, body fat, and progress photos together—so you can tell growth from noise.',
    framingLine: 'Build deliberately. See the whole trend.',
  },
};

export const LANDING_PRODUCT_PROOF = {
  src: productAssets.weightLog.publicUrl,
  alt: 'Real LogYourBody iPhone weight log showing the latest synced weight and recent entries',
  width: productAssets.weightLog.width,
  height: productAssets.weightLog.height,
  sourceKind: productAssets.weightLog.sourceKind,
  truthStatus: productAssets.weightLog.truthStatus,
  capturedAt: productAssets.weightLog.capturedAt,
} as const;

export const LANDING_BRAND_ASSET = {
  src: productAssets.appIcon.publicUrl,
  width: productAssets.appIcon.width,
  height: productAssets.appIcon.height,
  alt: 'LogYourBody app icon',
} as const;

export const LANDING_EXPERIMENTS = {
  audienceCreativeV1: {
    id: 'landing-audience-creative-v1',
    status: 'active',
    hypothesis:
      'Campaign-matched editorial creative will increase confirmed waitlist conversion versus unmatched creative.',
    primaryMetric: 'web_waitlist_submitted / unique web_landing_viewed',
    baselineConversionRate: 0.15,
    minimumDetectableAbsoluteLift: 0.05,
    sampleSizePerArm: 903,
    allocation: { men: 50, women: 50 },
    startedAt: '2026-07-14',
    killDate: '2026-08-13',
  },
  goalMessageV1: {
    id: 'landing-goal-message-v1',
    status: 'planned',
    variants: ['fat-loss', 'muscle-gain'],
    launchAfter: 'landing-audience-creative-v1',
  },
} as const;

export function isLandingAudience(value: unknown): value is LandingAudience {
  return typeof value === 'string' && LANDING_AUDIENCES.includes(value as LandingAudience);
}

export function isLandingGoal(value: unknown): value is LandingGoal {
  return typeof value === 'string' && LANDING_GOALS.includes(value as LandingGoal);
}

export function resolveLandingVariant(request: LandingVariantRequest): LandingVariant {
  const audience = isLandingAudience(request.audience) ? request.audience : 'men';
  const goal = isLandingGoal(request.goal) ? request.goal : 'recomposition';
  const media = LANDING_MEDIA[audience];
  const copy = LANDING_GOAL_COPY[goal];

  return {
    audience,
    goal,
    heroImage: media.src,
    heroAlt: media.alt,
    ...copy,
  };
}

export function buildLandingSource({
  audience,
  goal,
  assignmentSource,
}: {
  audience: LandingAudience;
  goal: LandingGoal;
  assignmentSource: LandingAssignmentSource;
}) {
  return `landing:v2:${audience}:${goal}:${assignmentSource}`;
}
