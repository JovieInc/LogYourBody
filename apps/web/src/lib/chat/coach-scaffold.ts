import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ProductUserRecord } from '@/lib/ports/user-directory';
import { coachPersonaGuardrailsEnabled } from '@/lib/flags/coach-persona';

export type LicensedCoachSource = {
  id: string;
  title: string;
  licenseId: string;
};

/**
 * TODO(LYB-89): RP Strength (Renaissance Periodization) rights are unconfirmed.
 * Do not ingest, embed, train on, or quote that material.
 * Add a source here only after a written license id exists, and keep blocked publishers out.
 */
export const LICENSED_COACH_SOURCES: readonly LicensedCoachSource[] = [];

const BLOCKED_PUBLISHER =
  /renaissance\s+periodization|\brp\s*strength\b|mike\s+israetel|\bisraetel\b/i;

const CONDITION =
  'diabetes|hypertension|high blood pressure|obesity|cancer|depression|anxiety|pcos|polycystic ovary syndrome|hypothyroidism|hyperthyroidism|eating disorder|heart disease|medical condition|health condition|disease|disorder';

const MEDICATION =
  /\b(?:medication|medicine|drug|dose|dosage|prescription|pill|tablet|injection|glp-?1|semaglutide|tirzepatide|ozempic|wegovy|mounjaro|zepbound|ibuprofen|metformin|insulin|statin)\b/i;

const DIRECTION_SOURCE =
  '\\b(?:prescri(?:be|bes|bed|bing)|you should take|take|start|stop|increase|decrease|adjust|titrat(?:e|es|ed|ing|ion))\\b';

const RULES: Array<{
  id: string;
  source: string;
  needsMedication?: boolean;
  needsDoseContext?: boolean;
}> = [
  {
    id: 'diagnosis',
    source: `\\b(?:diagnos(?:e|is|es|ed|ing)|you(?:'re| are) diagnosed(?: with)?|(?:you have|this means you have|this indicates you have|this is)\\s+(?:a |an )?(?:${CONDITION}))\\b`,
  },
  {
    id: 'drug-direction',
    source: DIRECTION_SOURCE,
    needsMedication: true,
  },
  {
    id: 'dose-amount',
    source: '\\b\\d+(?:\\.\\d+)?\\s*(?:mg|mcg|µg|ml)\\b',
    needsDoseContext: true,
  },
];

export const CLINICAL_GUARDRAIL_FALLBACK =
  "I can't diagnose a condition or prescribe medication or other drugs. Please contact a qualified healthcare professional. I can help with general exercise information.";

function isNegated(text: string, index: number): boolean {
  const prefix = text.slice(Math.max(0, index - 80), index);
  return /\b(?:do not|don't|does not|doesn't|did not|didn't|must not|should not|cannot|can't|never|avoid|without)\s+(?:[\w'-]+\s+){0,5}$/i.test(
    prefix,
  );
}

export function clinicalGuardrailViolation(text: string): string | null {
  const mentionsMedication = MEDICATION.test(text);
  const mentionsDirection = new RegExp(DIRECTION_SOURCE, 'i').test(text);
  for (const rule of RULES) {
    for (const match of text.matchAll(new RegExp(rule.source, 'gi'))) {
      const index = match.index ?? 0;
      if (isNegated(text, index)) continue;
      if (rule.needsMedication && !mentionsMedication) continue;
      if (rule.needsDoseContext && !mentionsMedication && !mentionsDirection) continue;
      return rule.id;
    }
  }
  return null;
}

export function applyClinicalGuardrail(content: string, enabled: boolean): string {
  if (!enabled) return content;
  return clinicalGuardrailViolation(content) ? CLINICAL_GUARDRAIL_FALLBACK : content;
}

export function holdCoachReplyForReview(trainingTurn: boolean, enabled: boolean): boolean {
  return trainingTurn || enabled;
}

export function vetLicensedSource(source: LicensedCoachSource): LicensedCoachSource {
  if (!source.id.trim() || !source.title.trim() || !source.licenseId.trim()) {
    throw new Error('unlicensed_source');
  }
  const label = `${source.id} ${source.title} ${source.licenseId}`;
  if (BLOCKED_PUBLISHER.test(label)) throw new Error('rp_strength_rights_unconfirmed');
  return source;
}

export function licensedSourceInstruction(): string {
  if (LICENSED_COACH_SOURCES.length === 0) {
    return 'No licensed evidence sources are configured. Do not quote, paraphrase, or attribute unlicensed coaching material.';
  }
  const vetted = LICENSED_COACH_SOURCES.map((source) => vetLicensedSource(source));
  return `Use only these licensed source ids: ${vetted.map((source) => source.id).join(', ')}.`;
}

export function coachPersonaAppendix(enabled = coachPersonaGuardrailsEnabled()): string {
  if (!enabled) return '';
  return `\n\nCoach persona: You are a fitness and body-composition coach, not a clinician. Never diagnose a condition. Never prescribe medication, drugs, doses, or treatment changes. Health and body data stay in this LogYourBody context. Do not request, repeat, or combine Jovie account data such as email, phone, display name, or avatar with that health data. ${licensedSourceInstruction()}`;
}

export type CoachHealthContext = {
  profile: {
    height: number | null;
    heightUnit: string | null;
    goalWeight: number | null;
    goalWeightUnit: string | null;
  } | null;
  recentMetrics: Array<{
    date: string;
    weight: number | null;
    weightUnit: 'kg' | 'lbs';
    bodyFatPercentage: number | null;
    muscleMass: number | null;
  }>;
};

export type JovieAccountProjection = {
  subject: string;
  email: string | null;
  phoneNumber: string | null;
  displayName: string | null;
  avatarUrl: string | null;
};

function compactProfile(user: ProductUserRecord | null): CoachHealthContext['profile'] {
  if (!user) return null;
  const profile = user.profileData;
  return {
    height: typeof profile.height === 'number' ? profile.height : null,
    heightUnit: typeof profile.height_unit === 'string' ? profile.height_unit : null,
    goalWeight: typeof profile.goal_weight === 'number' ? profile.goal_weight : null,
    goalWeightUnit: typeof profile.goal_weight_unit === 'string' ? profile.goal_weight_unit : null,
  };
}

function compactMetrics(metrics: ProductBodyMetric[]): CoachHealthContext['recentMetrics'] {
  return metrics.slice(0, 30).map((metric) => ({
    date: metric.date,
    weight: metric.weight,
    weightUnit: metric.weight_unit,
    bodyFatPercentage: metric.body_fat_percentage,
    muscleMass: metric.muscle_mass,
  }));
}

export function splitCallerContext(
  user: ProductUserRecord | null,
  metrics: ProductBodyMetric[],
): { health: CoachHealthContext; account: JovieAccountProjection | null } {
  return {
    health: {
      profile: compactProfile(user),
      recentMetrics: compactMetrics(metrics),
    },
    account: user
      ? {
          subject: user.subject,
          email: user.email ?? null,
          phoneNumber: user.phoneNumber ?? null,
          displayName: user.displayName ?? null,
          avatarUrl: user.avatarUrl ?? null,
        }
      : null,
  };
}

export function contextsCrossShare(split: {
  health: CoachHealthContext;
  account: JovieAccountProjection | null;
}): boolean {
  if (!split.account) return false;
  const healthText = JSON.stringify(split.health);
  const accountText = JSON.stringify(split.account);
  const accountValues = Object.values(split.account).filter(
    (value): value is string => typeof value === 'string' && value.length > 0,
  );
  if (accountValues.some((value) => healthText.includes(value))) return true;
  return split.health.recentMetrics.some((metric) => accountText.includes(metric.date));
}
