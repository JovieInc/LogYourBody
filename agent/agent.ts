import { defineAgent } from 'eve';
import { mockModel } from 'eve/evals';
import {
  connectionInstruction,
  localConnectionFixture,
  smokeReply,
} from './lib/account-connection';

const isLocalSmokeEval = process.env.LYB_EVE_LOCAL_SMOKE === '1';

/**
 * The external eve.dev runtime for LogYourBody's core agent chat. Product data
 * stays behind authenticated, consent-aware first-party ports; this definition
 * never grants data access by itself.
 */
export default defineAgent({
  model: isLocalSmokeEval
    ? mockModel(({ messages, tools, userMessageCount }) => {
        const state = localConnectionFixture();
        const systemInstructions = messages
          .filter((message) => message.role === 'system')
          .map((message) => message.text)
          .join('\n');
        const forbiddenTools = new Set([
          'agent',
          'bash',
          'glob',
          'grep',
          'read_file',
          'todo',
          'web_fetch',
          'web_search',
          'write_file',
        ]);

        if (!systemInstructions.includes(connectionInstruction(state))) {
          return 'Account-connection instruction was not applied.';
        }
        if (tools.some((tool) => forbiddenTools.has(tool.name))) {
          return 'A forbidden general-purpose tool is available.';
        }

        return smokeReply(state, userMessageCount);
      })
    : 'openai/gpt-5.4-mini',
  ...(isLocalSmokeEval
    ? {
        modelContextWindowTokens: 16_384,
        compaction: { modelContextWindowTokens: 16_384 },
      }
    : {}),
});
