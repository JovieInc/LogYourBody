import type { AgentModelOptionsDefinition } from 'eve';

/** Same switch as `apps/web/src/lib/ai/zero-retention.ts`. Default off. */
export const AI_ZERO_RETENTION_ENV = 'LYB_AI_ZERO_RETENTION';

/**
 * Gateway ZDR and OpenAI `store: false` for the eve model call.
 * Omitted unless the flag is on, because an ineligible gateway route fails the turn.
 * eve 0.27 cannot set durable run retention from agent config.
 */
export function providerZeroRetentionModelOptions(
  env: Record<string, string | undefined> = process.env,
): AgentModelOptionsDefinition | undefined {
  if (env[AI_ZERO_RETENTION_ENV] !== '1') return undefined;
  return {
    providerOptions: {
      gateway: { zeroDataRetention: true },
      openai: { store: false },
    },
  };
}
