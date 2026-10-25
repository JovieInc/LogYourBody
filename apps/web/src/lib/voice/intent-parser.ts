export type VoiceWeightUnit = 'kg' | 'lbs';

export type VoiceLogContext = {
  sessionId?: string;
  exercises?: Array<{ id: string; name: string }>;
  weightUnit?: VoiceWeightUnit;
  currentSet?: VoiceSetContext;
  lastCompletedSet?: VoiceSetContext;
};

export type VoiceSetContext = {
  exerciseId: string;
  exerciseName: string;
  setNumber: number;
  reps: number;
  loadKg: number | null;
  rir: number;
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
      kind: 'workout_feedback';
      requiresConfirmation: true;
      feedback: {
        sessionId: string;
        exerciseId: string;
        setNumber: number;
        intent:
          | 'breathing_limited'
          | 'grip_limited'
          | 'more_rest'
          | 'ready'
          | 'unusually_weak'
          | 'unknown';
        originalStatement: string;
      };
    }
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
    }
  | {
      kind: 'correct_set';
      requiresConfirmation: true;
      missingFields: string[];
      proposal: VoiceLogProposal | null;
    }
  | {
      kind: 'workout_action';
      requiresConfirmation: boolean;
      action:
        | { kind: 'equipment_unavailable'; exerciseId: string }
        | { kind: 'shorten'; minutes: number }
        | { kind: 'skip'; exerciseId: string }
        | { kind: 'pain'; exerciseId: string }
        | { kind: 'pause' }
        | { kind: 'resume' }
        | { kind: 'end' };
    };

const REP_PATTERN = /\b(\d{1,2})\s*reps?\b/i;
const LOAD_PATTERN =
  /\b(?:at|with)\s+(\d{1,3}(?:\.\d{1,2})?)\s*(kg|kgs|kilograms?|lb|lbs|pounds?)?\b/i;
const RIR_PATTERN = /\b(\d)\s*(?:rir|reps?\s+in\s+reserve|left)\b/i;
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

const SPOKEN_NUMBERS: Record<string, number> = {
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
  thirty: 30,
  forty: 40,
  fifty: 50,
};

function normalizeSpokenNumbers(value: string): string {
  return value.replace(
    /\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty)\b/gi,
    (word) => String(SPOKEN_NUMBERS[word.toLowerCase()]),
  );
}

function contextualAction(
  kind: 'equipment_unavailable' | 'skip' | 'pain',
  context: VoiceLogContext,
  transcript: string,
): VoiceIntentResult {
  const normalized = normalizeExerciseName(transcript);
  const named = (context.exercises ?? []).filter((exercise) =>
    normalized.includes(normalizeExerciseName(exercise.name)),
  );
  const exerciseId = named.length === 1 ? named[0]?.id : context.currentSet?.exerciseId;
  return exerciseId
    ? {
        kind: 'workout_action',
        requiresConfirmation: kind !== 'pain',
        action: { kind, exerciseId },
      }
    : { kind: 'clarify', missingFields: ['exercise'] };
}

export function parseVoiceIntent(
  transcript: string,
  context: VoiceLogContext = {},
): VoiceIntentResult {
  const original = transcript.trim();
  const normalized = normalizeSpokenNumbers(original);
  if (/\b(?:hurts?|pain|painful|dizzy|faint|numb|tingling)\b/i.test(normalized))
    return contextualAction('pain', context, normalized);
  // Normalize controls only. LYB-114 evaluates the saved observation, not this parser.
  const readinessIntent = (
    [
      [/^(?:i(?:'m| am)\s+)?still out of breath[.!]?$/i, 'breathing_limited'],
      [/^my grip is limiting me[.!]?$/i, 'grip_limited'],
      [/^(?:i\s+)?need more rest[.!]?$/i, 'more_rest'],
      [/^(?:actually\s+)?(?:i am\s+|i'm\s+)?ready now[.!]?$/i, 'ready'],
      [/^that set was unusually weak[.!]?$/i, 'unusually_weak'],
      [/^(?:i don't know if i'm ready|not ready now)[.!]?$/i, 'unknown'],
    ] as const
  ).find(([pattern]) => pattern.test(original))?.[1];
  if (readinessIntent) {
    const set =
      readinessIntent === 'unusually_weak' ? context.lastCompletedSet : context.currentSet;
    if (!context.sessionId || !set) {
      return {
        kind: 'clarify',
        missingFields: [
          readinessIntent === 'unusually_weak' ? 'last_completed_set' : 'current_set',
        ],
      };
    }
    return {
      kind: 'workout_feedback',
      requiresConfirmation: true,
      feedback: {
        sessionId: context.sessionId,
        exerciseId: set.exerciseId,
        setNumber: set.setNumber,
        intent: readinessIntent,
        originalStatement: original,
      },
    };
  }
  if (/\b(?:taken|occupied|unavailable|in use|not available)\b/i.test(normalized))
    return contextualAction('equipment_unavailable', context, normalized);
  const minutes = Number(/\b(\d{1,3})\s*(?:minutes?|mins?)\b/i.exec(normalized)?.[1]);
  if (/\b(?:only\s+have|have only|shorten|short on time)\b/i.test(normalized)) {
    return Number.isInteger(minutes) && minutes >= 5 && minutes <= 180
      ? {
          kind: 'workout_action',
          requiresConfirmation: true,
          action: { kind: 'shorten', minutes },
        }
      : { kind: 'clarify', missingFields: ['minutes'] };
  }
  if (/\bskip(?:\s+this)?(?:\s+today)?\b/i.test(normalized))
    return contextualAction('skip', context, normalized);
  if (/^(?:please\s+)?pause(?:\s+(?:the\s+)?(?:session|workout))?[.!]?$/i.test(normalized))
    return { kind: 'workout_action', requiresConfirmation: false, action: { kind: 'pause' } };
  if (/^(?:please\s+)?resume(?:\s+(?:the\s+)?(?:session|workout))?[.!]?$/i.test(normalized))
    return { kind: 'workout_action', requiresConfirmation: false, action: { kind: 'resume' } };
  if (/\b(?:end|finish)\s+(?:the\s+)?(?:session|workout)\b/i.test(normalized))
    return { kind: 'workout_action', requiresConfirmation: true, action: { kind: 'end' } };

  const isCorrection = /\b(?:actually|correct(?:ion)?|instead|not)\b/i.test(normalized);
  const isLog = /^(?:please\s+)?(?:log|record)\b/i.test(normalized);
  const hasSetValues = REP_PATTERN.test(normalized) || RIR_PATTERN.test(normalized);
  if (!isCorrection && !isLog && !(context.currentSet && hasSetValues)) return { kind: 'message' };

  const correctionReps = /\bactually\s+(\d{1,2})\b/i.exec(normalized)?.[1];
  const reps = Number(REP_PATTERN.exec(normalized)?.[1] ?? correctionReps);
  const loadMatch = LOAD_PATTERN.exec(normalized);
  const loadValue = loadMatch ? Number(loadMatch[1]) : undefined;
  const spokenUnit = canonicalWeightUnit(loadMatch?.[2]);
  const weightUnit = spokenUnit ?? context.weightUnit;
  const parsedRir = Number(RIR_PATTERN.exec(normalized)?.[1]);
  const setNumber = Number(SET_PATTERN.exec(normalized)?.[1]);
  const missingFields: string[] = [];

  const contextualSet = isCorrection ? context.lastCompletedSet : context.currentSet;
  const resolvedReps = Number.isInteger(reps) ? reps : contextualSet?.reps;
  const rir = Number.isInteger(parsedRir) ? parsedRir : contextualSet?.rir;
  if (!Number.isInteger(resolvedReps) || resolvedReps! < 1 || resolvedReps! > 50)
    missingFields.push('reps');
  if (!Number.isInteger(rir) || rir! < 0 || rir! > 6) missingFields.push('rir');
  if (loadMatch && (!Number.isFinite(loadValue) || loadValue! < 0 || !weightUnit)) {
    missingFields.push('weight');
  }

  if (missingFields.length > 0) return { kind: 'clarify', missingFields };

  const loweredTranscript = normalizeExerciseName(normalized);
  const exerciseMatches = (context.exercises ?? [])
    .filter((exercise) => loweredTranscript.includes(normalizeExerciseName(exercise.name)))
    .sort((left, right) => right.name.length - left.name.length);
  const exercise =
    exerciseMatches.length === 1
      ? exerciseMatches[0]
      : contextualSet
        ? { id: contextualSet.exerciseId, name: contextualSet.exerciseName }
        : undefined;
  const missingContext: string[] = [];
  if (!context.sessionId) missingContext.push('session');
  if (!exercise) missingContext.push('exercise');
  const resolvedSetNumber = Number.isInteger(setNumber) ? setNumber : contextualSet?.setNumber;
  if (!Number.isInteger(resolvedSetNumber) || resolvedSetNumber! < 1 || resolvedSetNumber! > 10) {
    missingContext.push('set_number');
  }

  const loadKg =
    loadMatch && loadValue !== undefined && weightUnit === 'lbs'
      ? poundsToKg(loadValue)
      : loadMatch
        ? loadValue!
        : (contextualSet?.loadKg ?? null);
  if (loadKg !== null && loadKg > 500) return { kind: 'clarify', missingFields: ['weight'] };

  const proposal =
    missingContext.length === 0 && exercise && context.sessionId
      ? {
          sessionId: context.sessionId,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          setNumber: resolvedSetNumber!,
          reps: resolvedReps!,
          loadKg,
          rir: rir!,
        }
      : null;

  if (isCorrection) {
    return {
      kind: 'correct_set',
      requiresConfirmation: true,
      missingFields: missingContext,
      proposal,
    };
  }

  return {
    kind: 'log_set',
    requiresConfirmation: true,
    missingFields: missingContext,
    proposal,
    heard: {
      ...(Number.isInteger(resolvedSetNumber) ? { setNumber: resolvedSetNumber } : {}),
      reps: resolvedReps!,
      ...(loadMatch && loadValue !== undefined ? { loadValue } : {}),
      ...(weightUnit ? { weightUnit } : {}),
      ...(loadMatch ? { loadKg } : {}),
      rir: rir!,
    },
  };
}
