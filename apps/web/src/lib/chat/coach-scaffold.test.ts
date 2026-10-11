import { buildChatModelMessages } from './context';
import {
  CLINICAL_GUARDRAIL_FALLBACK,
  LICENSED_COACH_SOURCES,
  applyClinicalGuardrail,
  clinicalGuardrailViolation,
  coachPersonaAppendix,
  contextsCrossShare,
  holdCoachReplyForReview,
  licensedSourceInstruction,
  splitCallerContext,
  vetLicensedSource,
} from './coach-scaffold';
import {
  COACH_PERSONA_GUARDRAILS_FLAG,
  coachPersonaGuardrailsEnabled,
} from '@/lib/flags/coach-persona';
import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ProductUserRecord } from '@/lib/ports/user-directory';

const user: ProductUserRecord = {
  subject: 'jovie-subject-1',
  email: 'person@example.test',
  phoneNumber: '+15555550100',
  displayName: 'Case Person',
  avatarUrl: 'avatar-not-forwarded',
  profileData: {
    height: 170,
    height_unit: 'cm',
    goal_weight: 72,
    goal_weight_unit: 'kg',
    privateNote: 'not forwarded',
  },
};

const metric: ProductBodyMetric = {
  id: 'metric-1',
  user_subject: 'jovie-subject-1',
  date: '2026-09-25',
  weight: 72,
  weight_unit: 'kg',
  body_fat_percentage: 20,
  body_fat_method: 'dexa',
  muscle_mass: 55,
  waist: null,
  neck: null,
  hip: null,
  notes: 'not forwarded',
  photo_url: 'private-photo-not-forwarded',
  data_source: 'test',
  source_metadata: {},
  created_at: '2026-09-25T00:00:00Z',
  updated_at: '2026-09-25T00:00:00Z',
};

describe('coach persona flag', () => {
  const previous = process.env[COACH_PERSONA_GUARDRAILS_FLAG];

  afterEach(() => {
    if (previous === undefined) delete process.env[COACH_PERSONA_GUARDRAILS_FLAG];
    else process.env[COACH_PERSONA_GUARDRAILS_FLAG] = previous;
  });

  it('stays off unless the server env is exactly 1', () => {
    delete process.env[COACH_PERSONA_GUARDRAILS_FLAG];
    expect(coachPersonaGuardrailsEnabled()).toBe(false);
    expect(coachPersonaGuardrailsEnabled({ [COACH_PERSONA_GUARDRAILS_FLAG]: 'true' })).toBe(false);
    expect(coachPersonaGuardrailsEnabled({ [COACH_PERSONA_GUARDRAILS_FLAG]: '1' })).toBe(true);
    expect(coachPersonaAppendix(false)).toBe('');
    expect(holdCoachReplyForReview(false, false)).toBe(false);
    expect(holdCoachReplyForReview(true, false)).toBe(true);
  });
});

describe('clinical guardrails', () => {
  it('blocks diagnosis and medical or drug direction', () => {
    expect(clinicalGuardrailViolation('You have diabetes.')).toBe('diagnosis');
    expect(clinicalGuardrailViolation('I diagnose this as hypertension.')).toBe('diagnosis');
    expect(clinicalGuardrailViolation('Increase your semaglutide.')).toBe('drug-direction');
    expect(clinicalGuardrailViolation('You should take Wegovy.')).toBe('drug-direction');
    expect(clinicalGuardrailViolation('Take 0.25 mg of Ozempic.')).toBe('drug-direction');
  });

  it('leaves coaching, refusals, and the fallback itself alone', () => {
    expect(clinicalGuardrailViolation('Your weight trend is stable.')).toBeNull();
    expect(clinicalGuardrailViolation('Try 3 sets.')).toBeNull();
    expect(clinicalGuardrailViolation("I can't diagnose diabetes or prescribe medication.")).toBe(
      null,
    );
    expect(clinicalGuardrailViolation(CLINICAL_GUARDRAIL_FALLBACK)).toBeNull();
    expect(applyClinicalGuardrail('You have diabetes.', false)).toBe('You have diabetes.');
    expect(applyClinicalGuardrail('You have diabetes.', true)).toBe(CLINICAL_GUARDRAIL_FALLBACK);
    expect(applyClinicalGuardrail('Your weight trend is stable.', true)).toBe(
      'Your weight trend is stable.',
    );
  });
});

describe('health and Jovie account separation', () => {
  it('keeps health context and the Jovie account projection from sharing fields', () => {
    const split = splitCallerContext(user, [metric]);
    expect(split.health.profile).toEqual({
      height: 170,
      heightUnit: 'cm',
      goalWeight: 72,
      goalWeightUnit: 'kg',
    });
    expect(split.health.recentMetrics).toEqual([
      {
        date: '2026-09-25',
        weight: 72,
        weightUnit: 'kg',
        bodyFatPercentage: 20,
        muscleMass: 55,
      },
    ]);
    expect(split.account).toEqual({
      subject: 'jovie-subject-1',
      email: 'person@example.test',
      phoneNumber: '+15555550100',
      displayName: 'Case Person',
      avatarUrl: 'avatar-not-forwarded',
    });
    expect(contextsCrossShare(split)).toBe(false);
    expect(JSON.stringify(split.health)).not.toContain('person@example.test');
    expect(JSON.stringify(split.account)).not.toContain('2026-09-25');
    expect(JSON.stringify(split.health)).not.toContain('privateNote');
    expect(JSON.stringify(split.health)).not.toContain('private-photo-not-forwarded');
  });
});

describe('licensed source slot', () => {
  it('stays empty and rejects RP Strength until rights are confirmed', () => {
    expect(LICENSED_COACH_SOURCES).toEqual([]);
    expect(licensedSourceInstruction()).toContain('No licensed evidence sources are configured');
    expect(licensedSourceInstruction().toLowerCase()).not.toContain('renaissance');
    expect(coachPersonaAppendix(true).toLowerCase()).not.toContain('israetel');
    expect(() =>
      vetLicensedSource({
        id: 'rp-strength',
        title: 'RP Strength hypertrophy notes',
        licenseId: 'pending',
      }),
    ).toThrow('rp_strength_rights_unconfirmed');
    expect(() =>
      vetLicensedSource({
        id: 'position-stand',
        title: 'Consensus statement',
        licenseId: '',
      }),
    ).toThrow('unlicensed_source');
    expect(
      vetLicensedSource({
        id: 'acsm-2009',
        title: 'Progression models in resistance training',
        licenseId: 'publisher-license-acsm-2009',
      }).id,
    ).toBe('acsm-2009');
  });
});

describe('gated persona prompt', () => {
  const previous = process.env[COACH_PERSONA_GUARDRAILS_FLAG];

  afterEach(() => {
    if (previous === undefined) delete process.env[COACH_PERSONA_GUARDRAILS_FLAG];
    else process.env[COACH_PERSONA_GUARDRAILS_FLAG] = previous;
  });

  it('adds the persona only when the flag is on and still omits Jovie account data', () => {
    delete process.env[COACH_PERSONA_GUARDRAILS_FLAG];
    const [off] = buildChatModelMessages({
      user,
      metrics: [metric],
      conversationMessages: [],
    });
    expect(off.content).not.toContain('Coach persona:');
    expect(off.content).not.toContain('person@example.test');

    process.env[COACH_PERSONA_GUARDRAILS_FLAG] = '1';
    const [on] = buildChatModelMessages({
      user,
      metrics: [metric],
      conversationMessages: [],
    });
    expect(on.content).toContain('Never diagnose a condition');
    expect(on.content).toContain('Never prescribe medication');
    expect(on.content).toContain('Do not request, repeat, or combine Jovie account data');
    expect(on.content).not.toContain('person@example.test');
    expect(on.content).not.toContain('Case Person');
    expect(on.content).toContain('"weight":72');
  });
});
