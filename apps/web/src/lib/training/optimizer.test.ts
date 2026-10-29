import { mesocycleOptimizerEnabled } from '@/lib/flags/mesocycle-optimizer';
import { profileEquipment, substitutionCandidates } from './catalog';
import { certifyOptimization } from './optimizer-certification';
import {
  optimizationPlanFingerprint,
  optimizeMesocycle,
  PAIN_PAUSE_MESSAGE,
  type OptimizationChange,
  type OptimizationProposal,
  type PlanSession,
} from './optimizer';
import { decideMesocycleOptimization, optimizerRequestIsEnrollment } from './optimizer-review';
import {
  OPTIMIZER_EVIDENCE_VERSION,
  OPTIMIZER_RULES,
  type OptimizerRuleSet,
} from './optimizer-rules';
import { createProposalInputSchema } from './revision-contract';
import type { MuscleGroup, SetLog } from './types';

const AT = '2026-10-14T15:00:00.000Z';

function exercise(id: string, primaryMuscle: MuscleGroup, sets = 2, userEdited = false, name = id) {
  return { id, name, primaryMuscle, sets, ...(userEdited ? { userEdited: true } : {}) };
}

function session(
  id: string,
  day: PlanSession['day'],
  part: PlanSession['part'],
  exercises: ReturnType<typeof exercise>[],
  heartRateBpm?: number,
) {
  return { id, day, part, exercises, ...(heartRateBpm === undefined ? {} : { heartRateBpm }) };
}

function input(overrides: Record<string, unknown> = {}) {
  return {
    sessions: [
      session('mon', 'monday', 'any', [
        exercise('goblet_squat', 'quads', 2, false, 'Goblet squat'),
      ]),
    ],
    equipmentProfile: 'full_gym',
    locationId: 'gym-a',
    locationPermission: 'denied',
    stationGeography: 'colocated',
    ...overrides,
  };
}

function proposalFor(body: unknown, rules?: OptimizerRuleSet): OptimizationProposal {
  const result = optimizeMesocycle(body, rules);
  if (result.kind !== 'proposal') throw new Error('expected a proposal');
  return result.proposal;
}

function changesOf<Kind extends OptimizationChange['kind']>(
  proposal: OptimizationProposal,
  kind: Kind,
): Extract<OptimizationChange, { kind: Kind }>[] {
  return proposal.changes.filter(
    (change): change is Extract<OptimizationChange, { kind: Kind }> => change.kind === kind,
  );
}

function log(
  id: string,
  exerciseId: string,
  sessionId: string,
  setNumber: number,
  loadKg: number,
): SetLog {
  return {
    id,
    sessionId,
    exerciseId,
    setNumber,
    reps: 9,
    loadKg,
    rir: 2,
    completedAt: AT,
  };
}

const calfPair = [
  exercise('cable_lateral_raise', 'shoulders', 2, false, 'Cable lateral raise'),
  exercise('seated_calf_raise', 'calves', 2, false, 'Seated calf raise'),
];

describe('mesocycle optimizer golden fixtures', () => {
  it('flags wrist curls before pull-ups as possible grip interference', () => {
    const body = input({
      equipmentProfile: 'dumbbells',
      sessions: [
        session('pull', 'monday', 'any', [
          exercise('wrist_curl', 'biceps', 2, false, 'Dumbbell wrist curl'),
          exercise('pull_up', 'back', 2, false, 'Pull-up'),
        ]),
      ],
    });
    const proposal = proposalFor(body);
    const grip = proposal.findings.find((item) => item.code === 'possible_grip_interference');
    expect(grip?.message).toMatch(/possible grip interference/i);
    expect(grip?.confidence).toBe('low');
    expect(grip?.message).toMatch(/not a measured fatigue score/i);
    expect(changesOf(proposal, 'reorder')).toEqual([
      {
        kind: 'reorder',
        sessionId: 'pull',
        moveExerciseId: 'pull_up',
        beforeExerciseId: 'wrist_curl',
        ruleId: 'grip_interference_v1',
      },
    ]);
    expect(certifyOptimization(body, proposal).ok).toBe(true);
  });

  it('offers a non-competing calf pairing only when equipment and setup are feasible', () => {
    const feasible = input({
      sessions: [session('legs', 'tuesday', 'any', calfPair)],
      measuredTransitionMinutes: null,
    });
    const offered = proposalFor(feasible);
    expect(changesOf(offered, 'offer_superset')).toEqual([
      {
        kind: 'offer_superset',
        sessionId: 'legs',
        exerciseIds: ['cable_lateral_raise', 'seated_calf_raise'],
        ruleId: 'superset_feasibility_v1',
      },
    ]);
    expect(changesOf(offered, 'prompt')).toEqual([]);

    const separated = proposalFor({ ...feasible, stationGeography: 'separated' });
    expect(changesOf(separated, 'offer_superset')).toEqual([]);
    expect(changesOf(separated, 'limitation').map((change) => change.code)).toContain(
      'equipment_or_setup_infeasible',
    );

    const missingEquipment = proposalFor({ ...feasible, equipmentProfile: 'dumbbells' });
    expect(changesOf(missingEquipment, 'offer_superset')).toEqual([]);
    expect(changesOf(missingEquipment, 'limitation')[0]?.message).toMatch(/equipment/i);
    expect(changesOf(missingEquipment, 'prompt')).toEqual([]);

    const unknown = proposalFor({ ...feasible, stationGeography: 'unknown' });
    expect(changesOf(unknown, 'offer_superset')).toEqual([]);
    expect(changesOf(unknown, 'prompt').map((change) => change.code)).toEqual(['gym_geography']);

    const quiet = proposalFor(
      input({
        sessions: [session('solo', 'tuesday', 'any', [exercise('goblet_squat', 'quads')])],
        stationGeography: 'unknown',
      }),
    );
    expect(changesOf(quiet, 'prompt')).toEqual([]);
  });

  it('keeps a busy-gym superset decline on that gym only', () => {
    const feasible = input({
      sessions: [session('legs', 'tuesday', 'any', calfPair)],
      declineSupersets: { scope: 'location', muscle: 'calves', reason: 'busy_gym' },
    });
    const declined = proposalFor(feasible);
    expect(changesOf(declined, 'offer_superset')).toEqual([]);
    const retained = changesOf(declined, 'retain_preference');
    expect(retained).toHaveLength(1);
    expect(retained[0]?.preference).toMatchObject({
      scope: 'location',
      locationId: 'gym-a',
      muscle: 'calves',
      reason: 'busy_gym',
    });

    const sameGym = proposalFor(
      input({
        sessions: feasible.sessions,
        preferences: [retained[0]!.preference],
      }),
    );
    expect(changesOf(sameGym, 'offer_superset')).toEqual([]);

    const otherGym = proposalFor(
      input({
        sessions: feasible.sessions,
        locationId: 'gym-b',
        preferences: [retained[0]!.preference],
      }),
    );
    expect(changesOf(otherGym, 'offer_superset')).toHaveLength(1);

    const never = proposalFor(
      input({
        sessions: feasible.sessions,
        locationId: 'gym-b',
        declineSupersets: { scope: 'durable', muscle: 'calves', reason: 'never' },
      }),
    );
    const durable = changesOf(never, 'retain_preference')[0]?.preference;
    expect(durable).toMatchObject({ scope: 'durable', locationId: null, muscle: 'calves' });
    const stillBlocked = proposalFor(
      input({
        sessions: feasible.sessions,
        locationId: 'gym-c',
        preferences: [durable!],
      }),
    );
    expect(changesOf(stillBlocked, 'offer_superset')).toEqual([]);
  });

  it('does not inherit a location block from a detected gym without permission', () => {
    const proposal = proposalFor(
      input({
        locationId: null,
        locationPermission: 'denied',
        detectedLocationId: 'gym-secret',
        declineSupersets: { scope: 'location', muscle: 'calves', reason: 'busy_gym' },
        sessions: [session('legs', 'tuesday', 'any', calfPair)],
      }),
    );
    expect(proposal.resolvedLocation).toEqual({ id: null, source: 'unknown' });
    expect(JSON.stringify(proposal)).not.toContain('gym-secret');
    expect(changesOf(proposal, 'retain_preference')).toEqual([]);
    expect(changesOf(proposal, 'prompt').map((change) => change.code)).toContain(
      'location_permission',
    );
  });

  it('respects Wednesday AM/PM fatigue from the schedule and reported readiness', () => {
    const body = input({
      sessions: [
        session(
          'wed-am',
          'wednesday',
          'am',
          [exercise('goblet_squat', 'quads', 2, false, 'Goblet squat')],
          170,
        ),
        session(
          'wed-pm',
          'wednesday',
          'pm',
          [exercise('leg_press', 'quads', 2, false, 'Leg press')],
          150,
        ),
      ],
      readiness: [{ sessionId: 'wed-pm', reported: 'low' }],
    });
    const proposal = proposalFor(body);
    const overlap = proposal.findings.find((item) => item.code === 'same_day_local_overlap');
    expect(overlap?.muscle).toBe('quads');
    expect(overlap?.message).toMatch(/wednesday/i);
    expect(overlap?.message).toMatch(/not assumed recovered/i);
    expect(overlap?.message).toMatch(/reported readiness/i);
    expect(overlap?.message).not.toMatch(/heart rate|bpm/i);
    expect(changesOf(proposal, 'limitation').map((change) => change.code)).toContain(
      'no_recovery_opportunity',
    );
    expect(proposal.findings.some((item) => item.code === 'reported_low_readiness')).toBe(true);
    expect(JSON.stringify(proposal.changes)).not.toMatch(/"sets":1/);

    const calves = proposalFor(
      input({
        sessions: [
          session('am', 'wednesday', 'am', [exercise('seated_calf_raise', 'calves')]),
          session('pm', 'wednesday', 'pm', [exercise('standing_calf_raise', 'calves')]),
        ],
      }),
    );
    expect(
      calves.findings.some(
        (item) => item.code === 'same_day_local_overlap' && item.muscle === 'calves',
      ),
    ).toBe(true);

    const otherDays = proposalFor(
      input({
        sessions: [
          session('mon', 'monday', 'am', [exercise('goblet_squat', 'quads')]),
          session('wed', 'wednesday', 'pm', [exercise('leg_press', 'quads')]),
        ],
      }),
    );
    expect(otherDays.findings.some((item) => item.code === 'same_day_local_overlap')).toBe(false);

    const ready = proposalFor({
      ...body,
      readiness: [{ sessionId: 'wed-pm', reported: 'ready' }],
    });
    expect(ready.findings.some((item) => item.code === 'same_day_local_overlap')).toBe(true);
    expect(ready.findings.some((item) => item.code === 'reported_low_readiness')).toBe(false);
    const louderHeart = proposalFor({
      ...body,
      readiness: [{ sessionId: 'wed-pm', reported: 'ready' }],
      sessions: body.sessions.map((item) => ({
        ...item,
        heartRateBpm: item.id === 'wed-pm' ? 190 : 40,
      })),
    });
    expect(louderHeart.findings.map((item) => item.code)).toEqual(
      ready.findings.map((item) => item.code),
    );
  });

  it('preserves the Smith incline variant and its own history', () => {
    const logs = [
      log('incline-1', 'incline_dumbbell_press', 'old', 1, 30),
      log('incline-2', 'incline_dumbbell_press', 'old', 2, 30),
      log('smith-1', 'smith_incline_press', 'smith-session', 1, 40),
      log('smith-2', 'smith_incline_press', 'smith-session', 2, 42),
    ];
    const body = input({
      declaredEquipment: ['smith'],
      logs,
      targetRir: 2,
      sessions: [
        session('chest', 'friday', 'any', [
          exercise('incline_dumbbell_press', 'chest', 3, false, 'Incline dumbbell press'),
        ]),
      ],
      requestedSwaps: [
        {
          sessionId: 'chest',
          fromExerciseId: 'incline_dumbbell_press',
          toVariantId: 'smith_incline_press',
        },
      ],
    });
    const proposal = proposalFor(body);
    const swap = changesOf(proposal, 'swap_variant')[0];
    expect(swap).toMatchObject({
      fromExerciseId: 'incline_dumbbell_press',
      toVariantId: 'smith_incline_press',
      historyExerciseId: 'smith_incline_press',
      painFreeAssumption: false,
    });
    expect(swap?.prescription.id).toBe('smith_incline_press');
    expect(swap?.prescription.name).toBe('Smith machine incline press');
    expect(swap?.prescription.sets).toBe(3);
    expect(swap?.prescription.targetLoadKg).toBe(42);
    expect(swap?.prescription.targetLoadKg).not.toBe(30);
    // The optimizer lacks a session/equipment-specific execution allowlist.
    // A reviewed variant must not authorize additional in-session swaps.
    expect(swap?.prescription.substitutions).toEqual([]);
    expect(certifyOptimization(body, proposal).ok).toBe(true);

    const edited = proposalFor({
      ...body,
      sessions: [
        session('chest', 'friday', 'any', [
          exercise('incline_dumbbell_press', 'chest', 3, true, 'Incline dumbbell press'),
        ]),
      ],
    });
    expect(changesOf(edited, 'swap_variant')).toEqual([]);
    expect(edited.findings.some((item) => item.code === 'user_edit_preserved')).toBe(true);
  });

  it('states an explicit limitation when no alternative is feasible or pain is high', () => {
    const blocked = input({
      equipmentProfile: 'dumbbells',
      sessions: [
        session('hinge', 'monday', 'any', [
          exercise(
            'dumbbell_romanian_deadlift',
            'hamstrings',
            2,
            false,
            'Dumbbell Romanian deadlift',
          ),
        ]),
      ],
      pain: [
        { exerciseId: 'dumbbell_romanian_deadlift', jointPain: 2, concern: 'low_back_symptoms' },
      ],
    });
    const limitation = proposalFor(blocked);
    expect(changesOf(limitation, 'swap_variant')).toEqual([]);
    expect(changesOf(limitation, 'limitation')[0]).toMatchObject({
      code: 'no_feasible_alternative',
      message: expect.stringMatching(/No reviewed alternative/),
    });

    const paused = proposalFor({
      ...blocked,
      pain: [
        { exerciseId: 'dumbbell_romanian_deadlift', jointPain: 4, concern: 'low_back_symptoms' },
      ],
    });
    expect(changesOf(paused, 'safety_prompt')[0]?.message).toBe(PAIN_PAUSE_MESSAGE);
    expect(changesOf(paused, 'swap_variant')).toEqual([]);

    const conservative = proposalFor(
      input({
        equipmentProfile: 'dumbbells',
        sessions: [
          session('arms', 'monday', 'any', [
            exercise('dumbbell_curl', 'biceps', 2, false, 'Dumbbell curl'),
          ]),
        ],
        pain: [{ exerciseId: 'dumbbell_curl', jointPain: 2, concern: 'wrist_intolerance' }],
      }),
    );
    const alternative = changesOf(conservative, 'swap_variant')[0];
    expect(alternative?.toVariantId).toBe('lying_dumbbell_curl');
    expect(alternative?.painFreeAssumption).toBe(false);
    expect(alternative?.historyExerciseId).toBe('lying_dumbbell_curl');
    expect(
      conservative.findings.find((item) => item.code === 'conservative_alternative')?.message,
    ).toMatch(/not assumed to be pain-free/i);
  });

  it('claims saved minutes only from measured transitions with no safety or scheduling compromise', () => {
    const clean = input({
      sessions: [session('legs', 'tuesday', 'any', calfPair)],
      measuredTransitionMinutes: 20,
    });
    const saved = proposalFor(clean);
    expect(saved.tradeoff.timeSavedMinutes).toBe(20);
    expect(saved.tradeoff.timeSavedBasis).toBe('measured_transition');
    expect(saved.tradeoff.noCompromise).toBe(true);
    expect(saved.tradeoff.compromises).toEqual([]);
    expect(saved.rationale.join(' ')).toMatch(/20 minutes saved/);
    expect(saved.rationale.join(' ')).toMatch(/no safety, volume, or scheduling compromise/);

    const unmeasured = proposalFor({ ...clean, measuredTransitionMinutes: null });
    expect(unmeasured.tradeoff.timeSavedMinutes).toBeNull();
    expect(unmeasured.tradeoff.noCompromise).toBe(false);
    expect(unmeasured.rationale.join(' ')).toMatch(/not estimated/);
    expect(unmeasured.rationale.join(' ')).not.toMatch(/20 minutes/);

    const compromised = proposalFor({
      ...clean,
      sessions: [
        session('wed-am', 'wednesday', 'am', calfPair),
        session('wed-pm', 'wednesday', 'pm', [exercise('standing_calf_raise', 'calves')]),
      ],
    });
    expect(compromised.tradeoff.timeSavedMinutes).toBe(20);
    expect(compromised.tradeoff.noCompromise).toBe(false);
    expect(compromised.tradeoff.compromises).toContain('same_day_local_overlap');
    expect(compromised.rationale.join(' ')).not.toMatch(
      /no safety, volume, or scheduling compromise/,
    );
  });
});

describe('optimizer properties, mutated rules, and promotion', () => {
  it('is deterministic and ignores heart rate, preference order, and unrelated declines', () => {
    const withHeart = input({
      sessions: [session('legs', 'tuesday', 'any', calfPair, 180)],
      preferences: [
        {
          id: 'b',
          scope: 'durable',
          locationId: null,
          muscle: 'biceps',
          reason: 'never this muscle',
        },
        {
          id: 'a',
          scope: 'location',
          locationId: 'gym-z',
          muscle: 'hamstrings',
          reason: 'other gym',
        },
      ],
    });
    const reordered = {
      ...withHeart,
      sessions: [session('legs', 'tuesday', 'any', calfPair, 40)],
      preferences: [...(withHeart.preferences as unknown[])].reverse(),
    };
    expect(proposalFor(withHeart)).toEqual(proposalFor(reordered));

    const reversedExercises = proposalFor(
      input({
        sessions: [session('legs', 'tuesday', 'any', [...calfPair].reverse())],
      }),
    );
    expect(
      reversedExercises.findings.some((item) => item.code === 'possible_grip_interference'),
    ).toBe(false);
    expect(changesOf(reversedExercises, 'offer_superset')[0]?.exerciseIds).toEqual([
      'cable_lateral_raise',
      'seated_calf_raise',
    ]);

    const once = proposalFor(input());
    expect(proposalFor(input())).toEqual(once);
  });

  it('stops proposing a grip reorder once that order is already fixed', () => {
    const body = input({
      equipmentProfile: 'dumbbells',
      sessions: [
        session('pull', 'monday', 'any', [
          exercise('wrist_curl', 'biceps', 2, false, 'Dumbbell wrist curl'),
          exercise('pull_up', 'back', 2, false, 'Pull-up'),
        ]),
      ],
    });
    const first = proposalFor(body);
    const reorder = changesOf(first, 'reorder')[0]!;
    const original = (body.sessions as PlanSession[])[0]!;
    const moving = original.exercises.find((item) => item.id === reorder.moveExerciseId)!;
    const rest = original.exercises.filter((item) => item.id !== reorder.moveExerciseId);
    const index = rest.findIndex((item) => item.id === reorder.beforeExerciseId);
    rest.splice(index, 0, moving);
    const second = proposalFor({ ...body, sessions: [{ ...original, exercises: rest }] });
    expect(second.findings.some((item) => item.code === 'possible_grip_interference')).toBe(false);
    expect(changesOf(second, 'reorder')).toEqual([]);
  });

  it('does not treat wrist curls as a biceps substitute and does not assume a Smith machine', () => {
    const candidates = substitutionCandidates({
      primaryMuscle: 'biceps',
      currentExerciseId: 'dumbbell_curl',
      currentContribution: { biceps: 1 },
      available: profileEquipment('dumbbells'),
      preferTorsoSupport: true,
      maxTrunkDemand: 'low',
    });
    expect(candidates.some((variant) => variant.id === 'wrist_curl')).toBe(false);
    expect(profileEquipment('full_gym').has('smith')).toBe(false);
  });

  it('rejects invalid proposals, mutated rules, stale evidence, and user edits', () => {
    const gripBody = input({
      equipmentProfile: 'dumbbells',
      sessions: [
        session('am', 'wednesday', 'am', [
          exercise('wrist_curl', 'biceps', 2, false, 'Dumbbell wrist curl'),
          exercise('pull_up', 'back', 2, false, 'Pull-up'),
          exercise('seated_calf_raise', 'calves'),
        ]),
        session('pm', 'wednesday', 'pm', [exercise('standing_calf_raise', 'calves')]),
      ],
    });
    const valid = proposalFor(gripBody);
    expect(certifyOptimization(gripBody, valid).ok).toBe(true);

    const withoutGrip = {
      ...valid,
      findings: valid.findings.filter((item) => item.code !== 'possible_grip_interference'),
    };
    expect(certifyOptimization(gripBody, withoutGrip).ok).toBe(false);
    expect(
      certifyOptimization(gripBody, withoutGrip).ok === false &&
        certifyOptimization(gripBody, withoutGrip),
    ).toMatchObject({
      violations: expect.arrayContaining(['missing_possible_grip_interference']),
    });

    const mutated: OptimizerRuleSet = {
      ...OPTIMIZER_RULES,
      calvesSameDayException: true,
      annotations: {
        ...OPTIMIZER_RULES.annotations,
        wrist_curl: { grip: 'none', stationClass: 'dumbbell' },
      },
    };
    const drifted = proposalFor(gripBody, mutated);
    const driftedVerdict = certifyOptimization(gripBody, drifted);
    expect(driftedVerdict.ok).toBe(false);
    if (!driftedVerdict.ok) {
      expect(driftedVerdict.violations).toEqual(
        expect.arrayContaining(['missing_possible_grip_interference', 'missing_same_day_overlap']),
      );
    }
    expect(
      decideMesocycleOptimization({
        source: gripBody,
        proposal: drifted,
        decision: 'apply',
        currentFingerprint: drifted.baseFingerprint,
        enabled: true,
      }).kind,
    ).toBe('not_certified');

    const timed = proposalFor(input({ sessions: [session('legs', 'tuesday', 'any', calfPair)] }));
    const claimed = {
      ...timed,
      tradeoff: {
        ...timed.tradeoff,
        timeSavedMinutes: 20,
        timeSavedBasis: 'measured_transition' as const,
        noCompromise: true,
      },
    };
    const claimedVerdict = certifyOptimization(
      input({ sessions: [session('legs', 'tuesday', 'any', calfPair)] }),
      claimed,
    );
    expect(claimedVerdict.ok).toBe(false);
    if (!claimedVerdict.ok) {
      expect(claimedVerdict.violations).toEqual(
        expect.arrayContaining(['unjustified_time_claim', 'false_no_compromise']),
      );
    }

    const applied = { ...valid, status: 'applied' as const };
    expect(certifyOptimization(gripBody, applied).ok).toBe(false);

    const smithBody = input({
      declaredEquipment: ['smith'],
      logs: [
        log('smith-1', 'smith_incline_press', 'smith-session', 1, 40),
        log('smith-2', 'smith_incline_press', 'smith-session', 2, 42),
        log('incline-1', 'incline_dumbbell_press', 'old', 1, 30),
        log('incline-2', 'incline_dumbbell_press', 'old', 2, 30),
      ],
      targetRir: 2,
      sessions: [
        session('chest', 'friday', 'any', [
          exercise('incline_dumbbell_press', 'chest', 3, false, 'Incline dumbbell press'),
        ]),
      ],
      requestedSwaps: [
        {
          sessionId: 'chest',
          fromExerciseId: 'incline_dumbbell_press',
          toVariantId: 'smith_incline_press',
        },
      ],
    });
    const smith = proposalFor(smithBody);
    const swap = changesOf(smith, 'swap_variant')[0]!;
    const rewritten = {
      ...smith,
      changes: smith.changes.map((change) =>
        change.kind === 'swap_variant'
          ? { ...change, prescription: { ...swap.prescription, targetLoadKg: 30 } }
          : change,
      ),
    };
    const history = certifyOptimization(smithBody, rewritten);
    expect(history.ok).toBe(false);
    if (!history.ok) expect(history.violations).toContain('variant_history_mismatch');

    const editedBody = input({
      equipmentProfile: 'dumbbells',
      sessions: [
        session('pull', 'monday', 'any', [
          exercise('wrist_curl', 'biceps', 2, false, 'Dumbbell wrist curl'),
          exercise('pull_up', 'back', 2, true, 'Pull-up'),
        ]),
      ],
    });
    const preserved = proposalFor(editedBody);
    const forced = {
      ...preserved,
      changes: [
        ...preserved.changes,
        {
          kind: 'reorder' as const,
          sessionId: 'pull',
          moveExerciseId: 'pull_up',
          beforeExerciseId: 'wrist_curl',
          ruleId: 'grip_interference_v1',
        },
      ],
    };
    const overwrite = certifyOptimization(editedBody, forced);
    expect(overwrite.ok).toBe(false);
    if (!overwrite.ok) expect(overwrite.violations).toContain('user_edit_overwritten');

    const stale = { ...valid, evidenceVersion: 'mesocycle-optimizer-rules-v0' };
    expect(certifyOptimization(gripBody, stale).ok).toBe(false);
    expect(
      decideMesocycleOptimization({
        source: gripBody,
        proposal: stale,
        decision: 'apply',
        currentFingerprint: stale.baseFingerprint,
        enabled: true,
      }),
    ).toEqual({ kind: 'stale_evidence' });
    expect(
      decideMesocycleOptimization({
        source: gripBody,
        proposal: valid,
        decision: 'apply',
        currentFingerprint: valid.baseFingerprint,
        currentEvidenceVersion: 'mesocycle-optimizer-rules-v0',
        enabled: true,
      }),
    ).toEqual({ kind: 'stale_evidence' });

    const editedPlan = decideMesocycleOptimization({
      source: gripBody,
      proposal: valid,
      decision: 'apply',
      currentFingerprint: optimizationPlanFingerprint([
        session('am', 'wednesday', 'am', [exercise('pull_up', 'back')]),
      ]),
      enabled: true,
    });
    expect(editedPlan.kind).toBe('user_edit_conflict');
    expect(editedPlan).not.toHaveProperty('changes');

    expect(
      decideMesocycleOptimization({
        source: gripBody,
        proposal: valid,
        decision: 'apply',
        currentFingerprint: valid.baseFingerprint,
        enabled: false,
      }),
    ).toEqual({ kind: 'disabled' });

    const rejected = decideMesocycleOptimization({
      source: gripBody,
      proposal: stale,
      decision: 'reject',
      currentFingerprint: 'ignored',
      enabled: true,
    });
    expect(rejected.kind).toBe('rejected');
    if (rejected.kind === 'rejected') {
      expect(rejected.receipt.writesPerformed).toBe(false);
      expect(rejected.receipt.enrollment).toBe(false);
    }

    const accepted = decideMesocycleOptimization({
      source: smithBody,
      proposal: smith,
      decision: 'apply',
      currentFingerprint: smith.baseFingerprint,
      enabled: true,
    });
    expect(accepted.kind).toBe('accepted');
    if (accepted.kind === 'accepted') {
      expect(accepted.receipt).toMatchObject({
        status: 'accepted',
        writesPerformed: false,
        enrollment: false,
        authority: 'self_review_required',
        evidenceVersion: OPTIMIZER_EVIDENCE_VERSION,
      });
      expect(accepted.changes.some((change) => change.kind === 'swap_variant')).toBe(true);
    }
  });

  it('stays off unless the flag is exactly true and cannot enroll through the revision command', () => {
    expect(mesocycleOptimizerEnabled({} as NodeJS.ProcessEnv)).toBe(false);
    expect(mesocycleOptimizerEnabled({ LYB_MESOCYCLE_OPTIMIZER_ENABLED: 'true' })).toBe(true);
    expect(mesocycleOptimizerEnabled({ LYB_MESOCYCLE_OPTIMIZER_ENABLED: '1' })).toBe(false);
    const proposal = proposalFor(input());
    expect(proposal.status).toBe('proposed');
    expect(proposal.persisted).toBe(false);
    expect(optimizerRequestIsEnrollment(proposal)).toBe(false);
    expect(createProposalInputSchema.safeParse(proposal).success).toBe(false);
    expect(proposal.evidenceVersion).toBe(OPTIMIZER_EVIDENCE_VERSION);
  });
});
