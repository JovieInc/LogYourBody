// Statsig environment tier for browser analytics.
//
// A production deployment must never report `development`. The tier is derived
// from the Vercel deployment environment (exposed to the client build as
// NEXT_PUBLIC_VERCEL_ENV by next.config.ts), so production does not depend on a
// separately configured NEXT_PUBLIC_STATSIG_ENV_TIER variable.
export const ANALYTICS_TIERS = ['production', 'staging', 'development'] as const;
export type AnalyticsTier = (typeof ANALYTICS_TIERS)[number];

export interface AnalyticsTierInputs {
  /** NEXT_PUBLIC_STATSIG_ENV_TIER: optional override for non-production builds. */
  explicit?: string | undefined;
  /** Vercel deployment environment: production | preview | development. */
  vercelEnv?: string | undefined;
  /** NODE_ENV of the build. */
  nodeEnv?: string | undefined;
}

function isAnalyticsTier(value: string | undefined): value is AnalyticsTier {
  return ANALYTICS_TIERS.some((tier) => tier === value);
}

export function resolveAnalyticsTier({
  explicit,
  vercelEnv,
  nodeEnv,
}: AnalyticsTierInputs): AnalyticsTier {
  // A production deployment is always production, whatever an override says.
  if (vercelEnv === 'production') return 'production';
  if (isAnalyticsTier(explicit)) return explicit;
  if (vercelEnv === 'preview') return 'staging';
  if (vercelEnv === 'development') return 'development';
  // No Vercel signal (for example a self-hosted production build).
  return nodeEnv === 'production' ? 'production' : 'development';
}

// Direct property reads (not dynamic lookups) so the client bundler inlines them.
export function analyticsTierFromEnv(): AnalyticsTier {
  return resolveAnalyticsTier({
    explicit: process.env.NEXT_PUBLIC_STATSIG_ENV_TIER,
    vercelEnv: process.env.NEXT_PUBLIC_VERCEL_ENV,
    nodeEnv: process.env.NODE_ENV,
  });
}
