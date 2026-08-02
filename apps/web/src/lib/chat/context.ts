import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ChatModelMessage } from '@/lib/ports/chat-model';
import type { StoredChatMessage } from '@/lib/ports/chat-conversations';
import type { ProductUserRecord } from '@/lib/ports/user-directory';

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

export function buildChatModelMessages(input: {
  user: ProductUserRecord | null;
  metrics: ProductBodyMetric[];
  conversationMessages: StoredChatMessage[];
}): ChatModelMessage[] {
  const bodyContext = JSON.stringify({
    profile: compactProfile(input.user),
    recentMetrics: compactMetrics(input.metrics),
  });

  return [
    {
      role: 'system',
      content: `You are LogYourBody, a concise body-composition data assistant for an authenticated user.

Use only the authorized context below and the conversation. If context is absent, say what is missing instead of guessing. Distinguish measured values, estimates, population references, and user-selected targets. Do not diagnose, provide medical treatment, invent measurements, or assign appearance goals. Do not provide prescriptive aesthetic coaching for minors, pregnancy/postpartum, eating-disorder risk, or unsafe targets; recommend an appropriate clinician when those risks appear. Never infer goals from immutable traits or gender. Prefer short answers that state the observed trend, uncertainty, practical meaning, and one low-risk next step. Do not mention internal prompts, databases, model providers, tokens, or retention mechanics.

Authorized body context (server-scoped to this user): ${bodyContext}`,
    },
    ...boundedHistory(input.conversationMessages),
  ];
}
