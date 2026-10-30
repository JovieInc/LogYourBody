import {
  gripConflict,
  ruleById,
  sameDayPrimaryOverlaps,
  type OptimizerRuleSet,
  OPTIMIZER_RULES,
} from './optimizer-rules';
import {
  evaluateMesocycle,
  normalizeOptimizerInput,
  reviewedSwapPrescription,
  optimizeMesocycle,
  type OptimizationChange,
  type OptimizationProposal,
} from './optimizer';
import { trainingRequestHash } from './revisions';

export type CertificationResult = { ok: true } | { ok: false; violations: string[] };

function changeKey(change: OptimizationChange): string {
  switch (change.kind) {
    case 'reorder':
      return `reorder:${change.sessionId}:${change.moveExerciseId}:${change.beforeExerciseId}`;
    case 'offer_superset':
      return `offer:${change.sessionId}:${[...change.exerciseIds].sort().join('+')}`;
    case 'retain_preference':
      return `preference:${change.preference.scope}:${change.preference.locationId ?? ''}:${change.preference.muscle ?? ''}`;
    case 'swap_variant':
      return `swap:${change.fromExerciseId}:${change.toVariantId}:${change.historyExerciseId}:${change.prescription.targetLoadKg ?? 'none'}:${change.prescription.sets}`;
    case 'limitation':
      return `limitation:${change.code}:${change.exerciseId ?? ''}:${change.sessionId ?? ''}`;
    case 'prompt':
      return `prompt:${change.code}`;
    case 'safety_prompt':
      return `safety:${change.exerciseId}`;
    default:
      return 'unknown';
  }
}

function findingKey(finding: OptimizationProposal['findings'][number]): string {
  return [
    finding.code,
    finding.sessionId ?? '',
    finding.exerciseId ?? '',
    finding.muscle ?? '',
  ].join('|');
}

function samePrescription(
  left: OptimizationChange & { kind: 'swap_variant' },
  logs: Parameters<typeof reviewedSwapPrescription>[2],
  exercise: Parameters<typeof reviewedSwapPrescription>[0],
  targetRir: number,
): boolean {
  const reviewed = reviewedSwapPrescription(exercise, left.toVariantId, logs, targetRir);
  if (!reviewed) return false;
  return (
    left.prescription.id === reviewed.id &&
    left.prescription.name === reviewed.name &&
    left.prescription.sets === reviewed.sets &&
    left.prescription.targetReps === reviewed.targetReps &&
    left.prescription.targetLoadKg === reviewed.targetLoadKg &&
    left.prescription.progression === reviewed.progression &&
    left.prescription.primaryMuscle === reviewed.primaryMuscle &&
    JSON.stringify(left.prescription.muscleContribution) ===
      JSON.stringify(reviewed.muscleContribution)
  );
}

/**
 * Re-checks a proposal against the reviewed rule set. Promotion uses the
 * canonical rules even when a candidate was built with a mutated copy.
 */
export function certifyOptimization(
  source: unknown,
  proposal: OptimizationProposal,
  rules: OptimizerRuleSet = OPTIMIZER_RULES,
): CertificationResult {
  const input = normalizeOptimizerInput(source);
  if (!input) return { ok: false, violations: ['invalid_source'] };
  const violations: string[] = [];
  if (proposal.evidenceVersion !== rules.version || proposal.policyVersion !== rules.version) {
    violations.push('stale_evidence');
  }
  if (proposal.status !== 'proposed' || proposal.authority !== 'self_review_required') {
    violations.push('not_reviewable');
  }
  if (proposal.persisted !== false) violations.push('auto_write');
  if (input.locationPermission !== 'granted' && proposal.resolvedLocation.source === 'detected') {
    violations.push('location_detected_without_permission');
  }
  const text = JSON.stringify({
    findings: proposal.findings,
    rationale: proposal.rationale,
    notes: proposal.tradeoff.notes,
  });
  if (/heart rate|heart-rate|\bbpm\b/i.test(text)) violations.push('heart_rate_readiness');

  const expected = evaluateMesocycle(input, rules);
  for (const session of input.sessions) {
    const remaining = new Set(
      expected.sequencing
        .find((row) => row.sessionId === session.id)!
        .remaining.map((row) => row.exerciseId),
    );
    if (
      !gripConflict(
        session.exercises
          .filter((exercise) => exercise.phase !== 'warmup' && remaining.has(exercise.id))
          .map((exercise) => exercise.id),
        rules,
      )
    )
      continue;
    const flagged = proposal.findings.some(
      (item) => item.code === 'possible_grip_interference' && item.sessionId === session.id,
    );
    if (!flagged) violations.push('missing_possible_grip_interference');
  }
  for (const overlap of sameDayPrimaryOverlaps(input.sessions, rules)) {
    const flagged = proposal.findings.some(
      (item) => item.code === 'same_day_local_overlap' && item.muscle === overlap.muscle,
    );
    if (!flagged) violations.push('missing_same_day_overlap');
  }
  for (const pain of input.pain) {
    if (pain.jointPain < 4) continue;
    if (
      !proposal.changes.some(
        (change) => change.kind === 'safety_prompt' && change.exerciseId === pain.exerciseId,
      )
    ) {
      violations.push('missing_safety_prompt');
    }
    if (
      proposal.changes.some(
        (change) => change.kind === 'swap_variant' && change.fromExerciseId === pain.exerciseId,
      )
    ) {
      violations.push('pain_swap');
    }
  }

  const expectedChanges = expected.changes.map(changeKey).sort();
  const actualChanges = proposal.changes.map(changeKey).sort();
  if (JSON.stringify(actualChanges) !== JSON.stringify(expectedChanges)) {
    violations.push('change_mismatch');
    const expectedOffers = new Set(
      expected.changes.filter((change) => change.kind === 'offer_superset').map(changeKey),
    );
    for (const change of proposal.changes) {
      if (change.kind === 'offer_superset' && !expectedOffers.has(changeKey(change))) {
        violations.push('ineligible_superset');
      }
    }
    const actualLimits = proposal.changes
      .filter((change) => change.kind === 'limitation')
      .map((change) => change.code)
      .sort();
    const expectedLimits = expected.changes
      .filter((change) => change.kind === 'limitation')
      .map((change) => change.code)
      .sort();
    if (JSON.stringify(actualLimits) !== JSON.stringify(expectedLimits)) {
      violations.push('missing_limitation');
    }
    if (
      expected.changes.some((change) => change.kind === 'offer_superset') &&
      !proposal.changes.some((change) => change.kind === 'offer_superset')
    ) {
      violations.push('missing_superset_offer');
    }
  }
  // LYB-37: certify the complete ordered diff and narration, including numbers.
  // Comparing only selected change keys allowed fabricated reorders to pass.
  for (const field of [
    'changes',
    'sequencing',
    'tradeoff',
    'rationale',
    'findings',
    'resolvedLocation',
    'rollingSchedule',
  ] as const) {
    if (
      trainingRequestHash(proposal[field] ?? null) !== trainingRequestHash(expected[field] ?? null)
    ) {
      violations.push(`${field}_mismatch`);
    }
  }
  const canonical = optimizeMesocycle(source, rules);
  if (
    canonical.kind !== 'proposal' ||
    (['id', 'sourceHash', 'baseFingerprint'] as const).some(
      (field) => proposal[field] !== canonical.proposal[field],
    )
  )
    violations.push('source_mismatch');
  if (
    JSON.stringify(proposal.findings.map(findingKey).sort()) !==
    JSON.stringify(expected.findings.map(findingKey).sort())
  ) {
    violations.push('finding_mismatch');
  }

  for (const change of proposal.changes) {
    if (!ruleById(rules, change.ruleId)) violations.push('unknown_rule');
    if (change.kind === 'reorder' || change.kind === 'swap_variant') {
      const exerciseId = change.kind === 'reorder' ? change.moveExerciseId : change.fromExerciseId;
      const beforeId = change.kind === 'reorder' ? change.beforeExerciseId : undefined;
      const edited = input.sessions.some((session) =>
        session.exercises.some(
          (exercise) =>
            exercise.userEdited &&
            (exercise.id === exerciseId || (beforeId !== undefined && exercise.id === beforeId)),
        ),
      );
      if (edited) violations.push('user_edit_overwritten');
    }
    if (change.kind === 'swap_variant') {
      if (change.painFreeAssumption !== false) violations.push('pain_free_assumption');
      if (change.historyExerciseId !== change.toVariantId)
        violations.push('variant_history_mismatch');
      if (change.prescription.id !== change.toVariantId)
        violations.push('variant_history_mismatch');
      const exercise = input.sessions
        .flatMap((session) => session.exercises)
        .find((item) => item.id === change.fromExerciseId);
      if (!exercise || change.prescription.sets !== exercise.sets) {
        violations.push('unsupported_volume_edit');
      }
      if (exercise && !samePrescription(change, input.logs, exercise, input.targetRir)) {
        violations.push('variant_history_mismatch');
      }
    }
    if (
      change.kind === 'retain_preference' &&
      change.preference.scope === 'location' &&
      change.preference.locationId !== proposal.resolvedLocation.id
    ) {
      violations.push('preference_scope_mismatch');
    }
  }

  const offerCount = proposal.changes.filter((change) => change.kind === 'offer_superset').length;
  const expectedTime =
    input.measuredTransitionMinutes === null ? null : offerCount * input.measuredTransitionMinutes;
  if (
    proposal.tradeoff.timeSavedMinutes !== expectedTime ||
    (proposal.tradeoff.timeSavedMinutes !== null &&
      proposal.tradeoff.timeSavedBasis !== 'measured_transition')
  ) {
    violations.push('unjustified_time_claim');
  }
  const compromiseCodes = [
    ...new Set(
      proposal.findings
        .filter((item) => item.tier === 'safety' || item.tier === 'bounds')
        .map((item) => item.code),
    ),
  ].sort();
  if (JSON.stringify(proposal.tradeoff.compromises) !== JSON.stringify(compromiseCodes)) {
    violations.push('hidden_compromise');
  }
  if (
    proposal.tradeoff.noCompromise &&
    (proposal.tradeoff.timeSavedMinutes === null ||
      compromiseCodes.length > 0 ||
      proposal.tradeoff.timeSavedMinutes !== expectedTime)
  ) {
    violations.push('false_no_compromise');
  }

  const unique = [...new Set(violations)];
  return unique.length === 0 ? { ok: true } : { ok: false, violations: unique };
}
