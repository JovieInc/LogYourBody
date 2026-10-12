export type VoiceWeightUnit = 'kg' | 'lbs';

export type VoiceLogContext = {
  sessionId?: string;
  exercises?: Array<{ id: string; name: string }>;
  weightUnit?: VoiceWeightUnit;
};

export type VoiceLogProposal = {
  sessionId: string;
  exerciseId: string;
  exerciseName: string;
  setNumber: number;
  reps: number;
  loadKg: number | null;
  rir: number;
};

export type VoiceIntentResult =
  | { kind: 'message' }
  | { kind: 'clarify'; missingFields: string[] }
  | {
      kind: 'log_set';
      requiresConfirmation: true;
      missingFields: string[];
      proposal: VoiceLogProposal | null;
      heard: {
        setNumber?: number;
        reps: number;
        loadValue?: number;
        weightUnit?: VoiceWeightUnit;
        loadKg?: number | null;
        rir: number;
      };
    };

const REP_PATTERN = /\b(\d{1,2})\s*reps?\b/i;
const LOAD_PATTERN =
  /\b(?:at|with)\s+(\d{1,3}(?:\.\d{1,2})?)\s*(kg|kgs|kilograms?|lb|lbs|pounds?)?\b/i;
const RIR_PATTERN = /\b(\d)\s*(?:rir|reps?\s+in\s+reserve)\b/i;
const SET_PATTERN = /\bset\s*(\d{1,2})\b/i;

export function poundsToKg(pounds: number): number {
  return Number((pounds * 0.45359237).toFixed(2));
}

function canonicalWeightUnit(unit: string | undefined): VoiceWeightUnit | undefined {
  if (!unit) return undefined;
  return /^(?:lb|lbs|pound|pounds)$/i.test(unit) ? 'lbs' : 'kg';
}

function normalizeExerciseName(value: string): string {
  return value
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function parseVoiceIntent(
  transcript: string,
  context: VoiceLogContext = {},
): VoiceIntentResult {
  const normalized = transcript.trim();
  if (!/^(?:please\s+)?(?:log|record)\b/i.test(normalized)) return { kind: 'message' };

  const reps = Number(REP_PATTERN.exec(normalized)?.[1]);
  const loadMatch = LOAD_PATTERN.exec(normalized);
  const loadValue = loadMatch ? Number(loadMatch[1]) : undefined;
  const spokenUnit = canonicalWeightUnit(loadMatch?.[2]);
  const weightUnit = spokenUnit ?? context.weightUnit;
  const rir = Number(RIR_PATTERN.exec(normalized)?.[1]);
  const setNumber = Number(SET_PATTERN.exec(normalized)?.[1]);
  const missingFields: string[] = [];

  if (!Number.isInteger(reps) || reps < 1 || reps > 50) missingFields.push('reps');
  if (!Number.isInteger(rir) || rir < 0 || rir > 6) missingFields.push('rir');
  if (loadMatch && (!Number.isFinite(loadValue) || loadValue! < 0 || !weightUnit)) {
    missingFields.push('weight');
  }

  if (missingFields.length > 0) return { kind: 'clarify', missingFields };

  const loweredTranscript = normalizeExerciseName(normalized);
  const exerciseMatches = (context.exercises ?? [])
    .filter((exercise) => loweredTranscript.includes(normalizeExerciseName(exercise.name)))
    .sort((left, right) => right.name.length - left.name.length);
  const exercise = exerciseMatches.length === 1 ? exerciseMatches[0] : undefined;
  const missingContext: string[] = [];
  if (!context.sessionId) missingContext.push('session');
  if (!exercise) missingContext.push('exercise');
  if (!Number.isInteger(setNumber) || setNumber! < 1 || setNumber! > 10) {
    missingContext.push('set_number');
  }

  const loadKg =
    loadMatch && loadValue !== undefined && weightUnit === 'lbs'
      ? poundsToKg(loadValue)
      : loadMatch
        ? loadValue!
        : null;
  if (loadKg !== null && loadKg > 500) return { kind: 'clarify', missingFields: ['weight'] };

  const proposal =
    missingContext.length === 0 && exercise && context.sessionId
      ? {
          sessionId: context.sessionId,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          setNumber,
          reps,
          loadKg,
          rir,
        }
      : null;

  return {
    kind: 'log_set',
    requiresConfirmation: true,
    missingFields: missingContext,
    proposal,
    heard: {
      ...(Number.isInteger(setNumber) ? { setNumber } : {}),
      reps,
      ...(loadMatch && loadValue !== undefined ? { loadValue } : {}),
      ...(weightUnit ? { weightUnit } : {}),
      ...(loadMatch ? { loadKg } : {}),
      rir,
    },
  };
}
