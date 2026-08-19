import { defineAgent } from 'eve';

/**
 * Private LYB Vercel Eve agent (not the Summer/Jovie internal Eve persona).
 *
 * Read-only product-discovery companion for Tim's gym dogfood sessions.
 * Vercel Eve discovers tools, channels, connections, schedules, subagents,
 * hooks, and sandbox overrides from the filesystem; those slots must stay
 * absent. Discovery notes stay private until a human sanitizes and files them.
 */
export default defineAgent({
  model: 'openai/gpt-5.4-mini',
});
