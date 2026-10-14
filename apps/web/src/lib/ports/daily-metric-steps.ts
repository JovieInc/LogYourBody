const MAX_STORED_STEPS = 2_147_483_647;

/** Keep legacy counts readable without treating an unmarked zero as observed. */
export function hasSafeDailyStepMeasurement(record: Record<string, unknown>): boolean {
  const steps = record.steps;
  const validCount =
    typeof steps === 'number' && Number.isInteger(steps) && steps >= 0 && steps <= MAX_STORED_STEPS;

  if (!Object.hasOwn(record, 'steps_present')) {
    return steps === undefined || steps === null || validCount;
  }
  if (record.steps_present === true) return validCount;
  if (record.steps_present === false) return steps === null;
  return false;
}
