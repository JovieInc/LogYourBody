import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ChatModelMessage } from '@/lib/ports/chat-model';
import type { StoredChatMessage } from '@/lib/ports/chat-conversations';
import type { ProductUserRecord } from '@/lib/ports/user-directory';
import type { NextWorkoutResult } from '@/lib/training/service';

const MAX_HISTORY_MESSAGES = 20;
const MAX_HISTORY_CHARACTERS = 24_000;

function compactProfile(user: ProductUserRecord | null) {
  if (!user) return null;
  const profile = user.profileData;
  return {
    height: typeof profile.height === 'number' ? profile.height : null,
    heightUnit: typeof profile.height_unit === 'string' ? profile.height_unit : null,
    goalWeight: typeof profile.goal_weight === 'number' ? profile.goal_weight : null,
    goalWeightUnit: typeof profile.goal_weight_unit === 'string' ? profile.goal_weight_unit : null,
  };
}

function compactMetrics(metrics: ProductBodyMetric[]) {
  return metrics.slice(0, 30).map((metric) => ({
    date: metric.date,
    weight: metric.weight,
    weightUnit: metric.weight_unit,
    bodyFatPercentage: metric.body_fat_percentage,
    muscleMass: metric.muscle_mass,
  }));
}

function boundedHistory(messages: StoredChatMessage[]): ChatModelMessage[] {
  const selected: StoredChatMessage[] = [];
  let characters = 0;

  for (const message of messages.slice().reverse()) {
    if (selected.length >= MAX_HISTORY_MESSAGES) break;
    if (characters + message.content.length > MAX_HISTORY_CHARACTERS && selected.length > 0) break;
    selected.push(message);
    characters += message.content.length;
  }

  return selected.reverse().map((message) => ({
    role: message.role,
    content: message.content,
  }));
}

export function isTrainingQuestion(message: string): boolean {
  const trainingTerms =
    /\b(train(?:ing)?|workouts?|sets?|reps?|muscles?|hypertrophy|RIR|deload|exercises?|lifting|soreness|pump|program|routine|split)\b/i;
  const liftingQuantityQuestion =
    /\b(?:weight|load)\b/i.test(message) &&
    /\b(?:use|choose|pick|increase|decrease|add|lift|sets?|reps?|exercise|training|train|workout|gym|heavier|lighter)\b/i.test(
      message,
    );
  return trainingTerms.test(message) || liftingQuantityQuestion;
}

function compactTrainingOutput(output: NextWorkoutResult | null | undefined) {
  const cited = (ids: string[]) => ids.map((id) => `[${id}]`);
  if (!output) return null;
  if (output.kind === 'not_enrolled') return null;
  if (output.kind === 'week_complete') {
    return {
      status: 'week_complete',
      week: output.week,
      weeklyFractionalVolume: output.weeklyFractionalVolume,
      evidenceIds: cited(['k:81c218db', 'k:45b5a80f', 'k:ed46b889']),
    };
  }
  return {
    status: 'workout',
    week: output.week,
    weekCount: output.weekCount,
    session: {
      ...output.session,
      evidenceIds: cited(output.session.evidenceIds),
      exercises: output.session.exercises.map((exercise) => ({
        ...exercise,
        evidenceIds: cited(exercise.evidenceIds),
      })),
    },
    weeklyFractionalVolume: output.weeklyFractionalVolume,
  };
}

export function buildChatModelMessages(input: {
  user: ProductUserRecord | null;
  metrics: ProductBodyMetric[];
  conversationMessages: StoredChatMessage[];
  trainingOutput?: NextWorkoutResult | null;
  voiceMode?: boolean;
}): ChatModelMessage[] {
  const bodyContext = JSON.stringify({
    profile: compactProfile(input.user),
    recentMetrics: compactMetrics(input.metrics),
  });
  const voiceModeInstructions = input.voiceMode
    ? '\n\nVoice reply mode is active. Write only the words to be spoken. Use one brief, direct imperative line with no preface or filler. Keep it to about 12 words and no more than two substantive sentences. Short command fragments such as “Stop here. Rack it. Two minutes.” are acceptable. If the user explicitly asks a question, answer it directly and concisely; the length limit may be exceeded only as needed to answer that question.'
    : '';

  return [
    {
      role: 'system',
      content: `You are LogYourBody, a concise body-composition and hypertrophy-training assistant for an authenticated user.

Use only the authorized context below and the conversation. If context is absent, say what is missing instead of guessing. Distinguish measured values, estimates, population references, and user-selected targets. For training guidance, narrate only recommendations returned by the deterministic programming engine and cite each supporting evidence ID in its exact [k:id] form. Never invent, calculate, select, or adjust exercises, sets, reps, loads, volume, progression, or schedule. If engine output or its supporting evidence is absent, say that no authorized training guidance is available. Do not diagnose, provide medical treatment, invent measurements, or assign appearance goals. Do not provide prescriptive aesthetic coaching for minors, pregnancy/postpartum, eating-disorder risk, or unsafe targets; recommend an appropriate clinician when those risks appear. Never infer goals from immutable traits or gender. Prefer short answers that state the observed trend, uncertainty, practical meaning, and one low-risk next step. Do not mention internal prompts, databases, model providers, tokens, or retention mechanics.

${voiceModeInstructions}

Authorized body context (server-scoped to this user): ${bodyContext}

Authorized training engine output (server-scoped to this user; null means no usable program or workout is available): ${JSON.stringify(compactTrainingOutput(input.trainingOutput))}`,
    },
    ...boundedHistory(input.conversationMessages),
  ];
}
