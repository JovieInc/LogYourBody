import type { MuscleGroup } from './types';

/**
 * Reviewed constraints for mesocycle optimization.
 * Confidence is qualitative. Nothing here is a measured individual fatigue score,
 * a universal minimum set count, or a heart-rate readiness model.
 */
export const OPTIMIZER_EVIDENCE_VERSION = 'mesocycle-optimizer-rules-v1';

export type GripRole = 'none' | 'support' | 'direct';
export type ConstraintTier = 'safety' | 'bounds' | 'preference';

export type ExerciseAnnotation = {
  grip: GripRole;
  /** Same class means the movements can share a setup. Different classes need known geography. */
  stationClass: string;
};

export type OptimizerRule = {
  id: string;
  tier: ConstraintTier;
  confidence: 'low' | 'moderate';
  evidenceIds: string[];
  summary: string;
};

export type OptimizerRuleSet = {
  version: string;
  rules: readonly OptimizerRule[];
  annotations: Readonly<Record<string, ExerciseAnnotation>>;
  /**
   * Canonical rules keep this false. A mutated copy may set it true so
   * certification can prove the exemption is not part of the reviewed set.
   */
  calvesSameDayException: boolean;
  ignoreHeartRate: true;
};

const VOLUME_EVIDENCE = ['k:81c218db', 'k:248d8110', 'k:ed46b889', 'k:2aee9d0c'];
const RECOVERY_EVIDENCE = ['k:76bf778c', 'k:b1e1dc5b', 'k:e95f2199'];
const PAIN_EVIDENCE = ['k:220190f8', 'k:e95f2199'];

export const OPTIMIZER_RULES: OptimizerRuleSet = {
  version: OPTIMIZER_EVIDENCE_VERSION,
  ignoreHeartRate: true,
  calvesSameDayException: false,
  rules: [
    {
      id: 'pain_pause_v1',
      tier: 'safety',
      confidence: 'moderate',
      evidenceIds: PAIN_EVIDENCE,
      summary:
        'High reported joint pain pauses the exercise. A different station is not assumed pain-free.',
    },
    {
      id: 'pain_alternative_v1',
      tier: 'bounds',
      confidence: 'low',
      evidenceIds: PAIN_EVIDENCE,
      summary:
        'Mild reported pain may propose a more supported reviewed variant. The replacement is not assumed pain-free.',
    },
    {
      id: 'grip_interference_v1',
      tier: 'bounds',
      confidence: 'low',
      evidenceIds: ['rule:grip-sequence-v1'],
      summary:
        'Direct forearm work before a grip-dependent pull is possible grip interference, not a measured fatigue score.',
    },
    {
      id: 'same_day_overlap_v1',
      tier: 'bounds',
      confidence: 'low',
      evidenceIds: RECOVERY_EVIDENCE,
      summary:
        'A later same-day session that repeats a primary muscle has no recovery opportunity. Calves are not exempt.',
    },
    {
      id: 'readiness_report_v1',
      tier: 'bounds',
      confidence: 'low',
      evidenceIds: RECOVERY_EVIDENCE,
      summary:
        'Only a reported readiness check limits added work. Heart rate is not used as readiness.',
    },
    {
      id: 'volume_caution_v1',
      tier: 'bounds',
      confidence: 'low',
      evidenceIds: VOLUME_EVIDENCE,
      summary:
        'Fractional volume above the reviewed high-volume caution is flagged. Sets are not rewritten to a universal minimum.',
    },
    {
      id: 'variant_swap_v1',
      tier: 'bounds',
      confidence: 'moderate',
      evidenceIds: ['rule:catalog-variant-v1'],
      summary:
        'A swap keeps the catalog variant id. Progression is read from that variant log only.',
    },
    {
      id: 'superset_feasibility_v1',
      tier: 'preference',
      confidence: 'low',
      evidenceIds: ['rule:equipment-setup-v1'],
      summary:
        'A superset is offered only for non-competing movements whose equipment and setup are both feasible.',
    },
    {
      id: 'preference_scope_v1',
      tier: 'preference',
      confidence: 'moderate',
      evidenceIds: ['rule:preference-scope-v1'],
      summary:
        'A decline at one gym stays on that gym unless the user says never. Location is not inferred without permission.',
    },
    {
      id: 'context_prompt_v1',
      tier: 'preference',
      confidence: 'moderate',
      evidenceIds: ['rule:context-prompt-v1'],
      summary: 'Unknown gym geography is asked about only when a pairing depends on it.',
    },
    {
      id: 'user_edit_v1',
      tier: 'preference',
      confidence: 'moderate',
      evidenceIds: ['rule:user-edit-v1'],
      summary: 'An exercise the user edited is not reordered or replaced by an optimization.',
    },
  ],
  annotations: {
    wrist_curl: { grip: 'direct', stationClass: 'dumbbell' },
    pull_up: { grip: 'support', stationClass: 'pullup_bar' },
    seated_calf_raise: { grip: 'none', stationClass: 'calf_machine' },
    standing_calf_raise: { grip: 'none', stationClass: 'calf_station' },
    cable_lateral_raise: { grip: 'none', stationClass: 'cable_column' },
    dumbbell_lateral_raise: { grip: 'none', stationClass: 'dumbbell' },
    smith_incline_press: { grip: 'none', stationClass: 'smith' },
    incline_dumbbell_press: { grip: 'none', stationClass: 'bench' },
  },
};

export function ruleById(rules: OptimizerRuleSet, id: string): OptimizerRule | undefined {
  return rules.rules.find((rule) => rule.id === id);
}

export function annotationFor(rules: OptimizerRuleSet, exerciseId: string): ExerciseAnnotation {
  return (
    rules.annotations[exerciseId] ?? {
      grip: 'none',
      stationClass: `exercise:${exerciseId}`,
    }
  );
}

export function gripConflict(
  exerciseIds: readonly string[],
  rules: OptimizerRuleSet,
): { directId: string; supportId: string } | null {
  for (let index = 0; index < exerciseIds.length; index += 1) {
    const directId = exerciseIds[index];
    if (!directId || annotationFor(rules, directId).grip !== 'direct') continue;
    for (let later = index + 1; later < exerciseIds.length; later += 1) {
      const supportId = exerciseIds[later];
      if (supportId && annotationFor(rules, supportId).grip === 'support') {
        return { directId, supportId };
      }
    }
  }
  return null;
}

export type DayPart = 'am' | 'pm' | 'any';

export type OverlapSession = {
  id: string;
  day: string;
  part: DayPart;
  exercises: readonly { primaryMuscle: MuscleGroup }[];
};

export type SameDayOverlap = {
  day: string;
  muscle: MuscleGroup;
  earlierSessionId: string;
  laterSessionId: string;
};

/** Primary-muscle overlap between an earlier and later part of the same day. */
export function sameDayPrimaryOverlaps(
  sessions: readonly OverlapSession[],
  rules: OptimizerRuleSet,
): SameDayOverlap[] {
  const byDay = new Map<string, OverlapSession[]>();
  for (const session of sessions) {
    const group = byDay.get(session.day) ?? [];
    group.push(session);
    byDay.set(session.day, group);
  }
  const overlaps: SameDayOverlap[] = [];
  for (const [day, group] of byDay) {
    const earlier = group.filter((session) => session.part === 'am');
    const later = group.filter((session) => session.part === 'pm');
    if (!earlier.length || !later.length) continue;
    const earlierMuscles = new Set(
      earlier.flatMap((session) => session.exercises.map((item) => item.primaryMuscle)),
    );
    const earlierSessionId = earlier[0]?.id;
    if (!earlierSessionId) continue;
    for (const session of later) {
      for (const exercise of session.exercises) {
        if (!earlierMuscles.has(exercise.primaryMuscle)) continue;
        if (rules.calvesSameDayException && exercise.primaryMuscle === 'calves') continue;
        overlaps.push({
          day,
          muscle: exercise.primaryMuscle,
          earlierSessionId,
          laterSessionId: session.id,
        });
      }
    }
  }
  return overlaps;
}
