import { defineAgent } from 'eve';
import { mockModel } from 'eve/evals';

const isLocalSmokeEval = process.env.LYB_EVE_LOCAL_SMOKE === '1';

/**
 * Private LYB Vercel Eve agent (not the Summer/Jovie internal Eve persona).
 *
 * Read-only product-discovery companion for Tim's gym dogfood sessions.
 * Vercel Eve discovers tools, channels, connections, schedules, subagents,
 * hooks, and sandbox overrides from the filesystem; those slots must stay
 * absent. Discovery notes stay private until a human sanitizes and files them.
 */
export default defineAgent({
  model: isLocalSmokeEval
    ? mockModel(
        ({ lastUserMessage, userMessageCount }) =>
          `LYB local smoke turn ${userMessageCount}: ${lastUserMessage}`,
      )
    : 'openai/gpt-5.4-mini',
  ...(isLocalSmokeEval
    ? {
        modelContextWindowTokens: 16_384,
        compaction: { modelContextWindowTokens: 16_384 },
      }
    : {}),
});
