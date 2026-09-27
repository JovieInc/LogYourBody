import type { NextWorkoutResult } from '@/lib/training/service';

type QuantityKind = 'sets' | 'reps' | 'rir' | 'load';

const NUMBER = String.raw`(?:\d+(?:\.\d+)?|a|an|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)`;
const NUMBER_WORDS: Record<string, number> = {
  a: 1,
  an: 1,
  zero: 0,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  eleven: 11,
  twelve: 12,
  thirteen: 13,
  fourteen: 14,
  fifteen: 15,
  sixteen: 16,
  seventeen: 17,
  eighteen: 18,
  nineteen: 19,
  twenty: 20,
};

function numericValue(value: string): number {
  return NUMBER_WORDS[value.toLowerCase()] ?? Number(value);
}

function allowedQuantities(
  output: NextWorkoutResult | null | undefined,
): Record<QuantityKind, Set<number>> {
  const allowed: Record<QuantityKind, Set<number>> = {
    sets: new Set(),
    reps: new Set(),
    rir: new Set(),
    load: new Set(),
  };
  if (output?.kind !== 'workout') return allowed;

  for (const exercise of output.session.exercises) {
    allowed.sets.add(exercise.sets);
    allowed.reps.add(exercise.targetReps);
    allowed.reps.add(exercise.repRange.min);
    allowed.reps.add(exercise.repRange.max);
    allowed.rir.add(exercise.targetRir);
    if (exercise.targetLoadKg !== null) allowed.load.add(exercise.targetLoadKg);
  }
  return allowed;
}

function supported(
  value: string,
  kind: QuantityKind,
  allowed: Record<QuantityKind, Set<number>>,
): boolean {
  const number = numericValue(value);
  return Number.isFinite(number) && allowed[kind].has(number);
}

/**
 * Fail closed when a training answer attaches a quantity to sets, reps, effort,
 * or load that the server's current engine result did not return.
 */
export function hasUnauthorizedTrainingQuantity(
  answer: string,
  output: NextWorkoutResult | null | undefined,
): boolean {
  const allowed = allowedQuantities(output);
  const check = (kind: QuantityKind, value: string | undefined) =>
    value !== undefined && !supported(value, kind, allowed);

  const valueBeforeUnit = new RegExp(
    `\\b(${NUMBER})\\s*(?:-|\\s)?\\s*(sets?|reps?|repetitions?|rir)\\b`,
    'gi',
  );
  for (const match of answer.matchAll(valueBeforeUnit)) {
    const kind = match[2]?.toLowerCase().startsWith('set')
      ? 'sets'
      : match[2]?.toLowerCase() === 'rir'
        ? 'rir'
        : 'reps';
    if (check(kind, match[1])) return true;
  }

  const rangeBeforeUnit = new RegExp(
    `\\b(${NUMBER})\\s*(?:-|–|to)\\s*(${NUMBER})\\s*(sets?|reps?|repetitions?|rir)\\b`,
    'gi',
  );
  for (const match of answer.matchAll(rangeBeforeUnit)) {
    const kind = match[3]?.toLowerCase().startsWith('set')
      ? 'sets'
      : match[3]?.toLowerCase() === 'rir'
        ? 'rir'
        : 'reps';
    if (check(kind, match[1]) || check(kind, match[2])) return true;
  }

  const valueAfterUnit = new RegExp(
    `\\b(sets?|reps?|repetitions?|rir)\\s*(?:of|to|at|:)?\\s*(${NUMBER})\\b(?!\\s*(?:sets?|reps?|repetitions?|rir)\\b)`,
    'gi',
  );
  for (const match of answer.matchAll(valueAfterUnit)) {
    const kind = match[1]?.toLowerCase().startsWith('set')
      ? 'sets'
      : match[1]?.toLowerCase() === 'rir'
        ? 'rir'
        : 'reps';
    if (check(kind, match[2])) return true;
  }

  const multiplication = new RegExp(
    `\\b(${NUMBER})\\s*[x×]\\s*(${NUMBER})(?:\\s*(?:-|–|to)\\s*(${NUMBER}))?\\b`,
    'gi',
  );
  for (const match of answer.matchAll(multiplication)) {
    if (check('sets', match[1]) || check('reps', match[2]) || check('reps', match[3])) return true;
  }

  const loadWithUnit = new RegExp(`\\b(${NUMBER})\\s*(?:kg|kilograms?|lbs?|pounds?)\\b`, 'gi');
  for (const match of answer.matchAll(loadWithUnit)) {
    if (check('load', match[1])) return true;
  }

  const loadByName = new RegExp(
    `\\b(?:load|weight)\\s*(?:(?:the|a|an)\\s+)?(?:(?:of|at|to|by|up to|:)\\s*)?(${NUMBER})\\b`,
    'gi',
  );
  for (const match of answer.matchAll(loadByName)) {
    if (check('load', match[1])) return true;
  }
  return false;
}
