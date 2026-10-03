import { defineAgent } from 'eve';
import { mockModel } from 'eve/evals';
import {
  connectionInstruction,
  localConnectionFixture,
  smokeReply,
} from './lib/account-connection';
import { knowledgeEvalFixtureModel } from './lib/knowledge-eval-fixture';
import { providerZeroRetentionModelOptions } from './lib/provider-zero-retention';
import { trainingToolGate } from './lib/training-tools';

const isLocalSmokeEval = process.env.LYB_EVE_LOCAL_SMOKE === '1';
const isKnowledgeSkillEval = process.env.LYB_EVE_KNOWLEDGE_EVAL === '1';
const zeroRetentionModelOptions = providerZeroRetentionModelOptions();

/**
 * The external eve.dev runtime for LogYourBody's core agent chat. Product data
 * stays behind authenticated, consent-aware first-party ports; this definition
 * never grants data access by itself.
 */
export default defineAgent({
  model: isKnowledgeSkillEval
    ? knowledgeEvalFixtureModel()
    : isLocalSmokeEval
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
        const requiredTrainingTools = new Set(['get_next_workout', 'log_set', 'record_feedback']);
        const gatePrincipal = {
          principalType: state === 'connected' ? 'user' : undefined,
          subject: state === 'connected' ? 'smoke-user' : undefined,
          attributes: { logYourBodyConnection: state },
        };
        const gateResult = trainingToolGate(gatePrincipal);

        if (!systemInstructions.includes(connectionInstruction(state))) {
          return 'Account-connection instruction was not applied.';
        }
        if (
          (state === 'connected' && gateResult.status !== 'first_party_auth_required') ||
          (state === 'unconnected' && gateResult.status !== 'connection_required')
        ) {
          return 'Training tools did not fail closed at the account-connection boundary.';
        }
        if (!systemInstructions.includes("Medication decisions and medication amounts are outside the coach's scope.")) {
          return 'Compliance guardrails were not applied.';
        }
        if (tools.some((tool) => forbiddenTools.has(tool.name))) {
          return 'A forbidden general-purpose tool is available.';
        }
        if ([...requiredTrainingTools].some((name) => !tools.some((tool) => tool.name === name))) {
          return 'Typed training tools are missing.';
        }

        return smokeReply(state, userMessageCount);
      })
    : 'openai/gpt-5.4-mini',
  ...(zeroRetentionModelOptions && !isLocalSmokeEval && !isKnowledgeSkillEval
    ? { modelOptions: zeroRetentionModelOptions }
    : {}),
  ...(isLocalSmokeEval || isKnowledgeSkillEval
    ? {
        modelContextWindowTokens: 16_384,
        compaction: { modelContextWindowTokens: 16_384 },
      }
    : {}),
});
