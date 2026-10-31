import { CATALOG_EQUIPMENT } from './catalog';
import { MUSCLE_GROUPS, type MuscleGroup, type TrainingFeedback } from './types';

export function validTrainingFeedback(
  value: unknown,
): value is Omit<TrainingFeedback, 'id' | 'createdAt'> {
  if (!value || typeof value !== 'object') return false;
  const feedback = value as Partial<TrainingFeedback>;
  const validScore = (score: unknown) =>
    typeof score === 'number' && Number.isInteger(score) && score >= 0 && score <= 10;
  const validOptionalScore = (score: unknown) => score === undefined || validScore(score);
  const validPerformance = (performance: unknown) =>
    performance === 'up' || performance === 'stable' || performance === 'down';
  const validReadiness = (readiness: unknown) =>
    readiness === 'ready' || readiness === 'limited' || readiness === 'unknown';
  const validOptionalString = (text: unknown, max: number) =>
    text === undefined ||
    (typeof text === 'string' && text.trim().length > 0 && text.length <= max);
  const validMuscleObservation = (observation: unknown) => {
    if (!observation || typeof observation !== 'object' || Array.isArray(observation)) return false;
    const item = observation as NonNullable<TrainingFeedback['muscles']>[MuscleGroup];
    return (
      validOptionalScore(item?.soreness) &&
      (item?.recovery === undefined || validReadiness(item.recovery)) &&
      validOptionalScore(item?.pump) &&
      (item?.workload === undefined ||
        item.workload === 'below_expected' ||
        item.workload === 'as_expected' ||
        item.workload === 'above_expected') &&
      (item?.performance === undefined || validPerformance(item.performance)) &&
      Object.values(item ?? {}).some((entry) => entry !== undefined)
    );
  };
  const muscles = feedback.muscles;
  const validMuscles =
    muscles === undefined ||
    (!Array.isArray(muscles) &&
      Object.keys(muscles).length > 0 &&
      Object.entries(muscles).every(
        ([muscle, observation]) =>
          MUSCLE_GROUPS.includes(muscle as MuscleGroup) && validMuscleObservation(observation),
      ));
  const supporting = feedback.supportingReadiness;
  const validSupporting =
    supporting === undefined ||
    (!Array.isArray(supporting) &&
      (supporting.grip === undefined || validReadiness(supporting.grip)) &&
      (supporting.trunk === undefined || validReadiness(supporting.trunk)) &&
      (supporting.muscles === undefined ||
        (!Array.isArray(supporting.muscles) &&
          Object.keys(supporting.muscles).length > 0 &&
          Object.entries(supporting.muscles).every(
            ([muscle, readiness]) =>
              MUSCLE_GROUPS.includes(muscle as MuscleGroup) && validReadiness(readiness),
          ))) &&
      (supporting.grip !== undefined ||
        supporting.trunk !== undefined ||
        supporting.muscles !== undefined));
  const context = feedback.context;
  const validContext =
    context === undefined ||
    (!Array.isArray(context) &&
      validOptionalString(context.exerciseId, 80) &&
      validOptionalString(context.setId, 160) &&
      (context.setNumber === undefined ||
        (Number.isInteger(context.setNumber) &&
          context.setNumber >= 1 &&
          context.setNumber <= 50)) &&
      (context.setOrder === undefined ||
        (Number.isInteger(context.setOrder) && context.setOrder >= 1 && context.setOrder <= 50)) &&
      (context.reps === undefined ||
        (Number.isInteger(context.reps) && context.reps >= 0 && context.reps <= 100)) &&
      (context.loadKg === undefined ||
        context.loadKg === null ||
        (Number.isFinite(context.loadKg) && context.loadKg >= 0 && context.loadKg <= 500)) &&
      (context.rir === undefined ||
        (Number.isInteger(context.rir) && context.rir >= 0 && context.rir <= 6)) &&
      (context.restSeconds === undefined ||
        (Number.isInteger(context.restSeconds) &&
          context.restSeconds >= 0 &&
          context.restSeconds <= 3600)) &&
      validOptionalString(context.setup, 160) &&
      validOptionalString(context.gymId, 80) &&
      (context.availableEquipment === undefined ||
        (Array.isArray(context.availableEquipment) &&
          context.availableEquipment.length <= CATALOG_EQUIPMENT.length &&
          context.availableEquipment.every((item) => CATALOG_EQUIPMENT.includes(item)))) &&
      (context.romRestriction === undefined ||
        ['none', 'limited', 'blocked'].includes(context.romRestriction)) &&
      (context.rangeOfMotion === undefined ||
        context.rangeOfMotion === 'full' ||
        context.rangeOfMotion === 'partial' ||
        context.rangeOfMotion === 'unknown') &&
      (context.setFormat === undefined || context.setFormat === 'straight'));
  const validSymptoms =
    feedback.symptomFlags === undefined ||
    (Array.isArray(feedback.symptomFlags) &&
      feedback.symptomFlags.length > 0 &&
      feedback.symptomFlags.length <= 3 &&
      feedback.symptomFlags.every(
        (flag) => flag === 'pain' || flag === 'neurologic' || flag === 'other_concerning',
      ));
  const validObservationIds = (ids: unknown) =>
    ids === undefined ||
    (Array.isArray(ids) &&
      ids.length > 0 &&
      ids.length <= 20 &&
      ids.every((id) => typeof id === 'string' && id.trim().length > 0 && id.length <= 160));
  const validClaims = new Set([
    'goal_preference',
    'self_assessed_development',
    'performance',
    'tolerability',
    'symptom',
    'recovery',
    'pump',
    'causal_hypothesis',
    'dose_history',
  ]);
  const validInterpretations =
    feedback.interpretations === undefined ||
    (Array.isArray(feedback.interpretations) &&
      feedback.interpretations.length > 0 &&
      feedback.interpretations.length <= 8 &&
      feedback.interpretations.every(
        (interpretation) =>
          validClaims.has(interpretation.claim) &&
          (interpretation.timeframe === 'current' || interpretation.timeframe === 'historical') &&
          (interpretation.confidence === 'low' ||
            interpretation.confidence === 'moderate' ||
            interpretation.confidence === 'high') &&
          validObservationIds(interpretation.corroboratesObservationIds) &&
          validObservationIds(interpretation.conflictsWithObservationIds) &&
          validOptionalString(interpretation.proposedExplanation, 500),
      ));
  const hasObservation = Boolean(
    feedback.soreness !== undefined ||
    feedback.pump !== undefined ||
    feedback.performance !== undefined ||
    feedback.jointPain !== undefined ||
    muscles !== undefined ||
    feedback.targetMuscleReadiness !== undefined ||
    feedback.breathingReadiness !== undefined ||
    feedback.generalReadiness !== undefined ||
    supporting !== undefined ||
    feedback.trunkFatigue !== undefined ||
    feedback.generalExhaustion !== undefined ||
    feedback.targetMuscleQuality !== undefined ||
    feedback.stability !== undefined ||
    feedback.symptomFlags !== undefined ||
    feedback.symptomNote !== undefined ||
    feedback.originalStatement !== undefined ||
    feedback.interpretations !== undefined,
  );
  return (
    typeof feedback.sessionId === 'string' &&
    feedback.sessionId.trim().length > 0 &&
    validOptionalScore(feedback.soreness) &&
    validOptionalScore(feedback.pump) &&
    (feedback.performance === undefined || validPerformance(feedback.performance)) &&
    validOptionalScore(feedback.jointPain) &&
    validMuscles &&
    (feedback.targetMuscle === undefined || MUSCLE_GROUPS.includes(feedback.targetMuscle)) &&
    (feedback.targetMuscleReadiness === undefined ||
      validReadiness(feedback.targetMuscleReadiness)) &&
    (feedback.breathingReadiness === undefined || validReadiness(feedback.breathingReadiness)) &&
    (feedback.generalReadiness === undefined || validReadiness(feedback.generalReadiness)) &&
    validSupporting &&
    validOptionalScore(feedback.trunkFatigue) &&
    validOptionalScore(feedback.generalExhaustion) &&
    (feedback.targetMuscleQuality === undefined ||
      ['poor', 'adequate', 'good'].includes(feedback.targetMuscleQuality)) &&
    (feedback.stability === undefined || ['stable', 'unstable'].includes(feedback.stability)) &&
    validSymptoms &&
    validOptionalString(feedback.symptomNote, 500) &&
    validOptionalString(feedback.originalStatement, 1_000) &&
    (feedback.transcriptionUncertain === undefined ||
      typeof feedback.transcriptionUncertain === 'boolean') &&
    validInterpretations &&
    (feedback.source === undefined ||
      feedback.source === 'touch' ||
      feedback.source === 'voice' ||
      feedback.source === 'text' ||
      feedback.source === 'import' ||
      feedback.source === 'unknown') &&
    (feedback.observedAt === undefined || Number.isFinite(Date.parse(feedback.observedAt))) &&
    validOptionalString(feedback.sourceObservationId, 160) &&
    validOptionalString(feedback.correctsObservationId, 160) &&
    validContext &&
    hasObservation
  );
}
