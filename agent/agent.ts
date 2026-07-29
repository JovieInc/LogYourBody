import { defineAgent } from 'eve';

/**
 * LYB's first eve agent: a private, read-only product-discovery companion for
 * Tim's gym dogfood sessions. No channels, connections, schedules, or tools are
 * enabled in this scaffold.
 */
export default defineAgent({
  model: 'openai/gpt-5.4-mini',
});
