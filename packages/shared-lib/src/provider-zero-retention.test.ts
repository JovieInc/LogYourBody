import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  AI_ZERO_RETENTION_ENV,
  providerZeroRetentionModelOptions,
} from '../../../agent/lib/provider-zero-retention';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

describe('eve provider zero retention', () => {
  it('omits gateway options unless the default-off flag is exactly 1', () => {
    expect(AI_ZERO_RETENTION_ENV).toBe('LYB_AI_ZERO_RETENTION');
    expect(providerZeroRetentionModelOptions({})).toBeUndefined();
    expect(providerZeroRetentionModelOptions({ LYB_AI_ZERO_RETENTION: 'true' })).toBeUndefined();
    expect(providerZeroRetentionModelOptions({ LYB_AI_ZERO_RETENTION: '1' })).toEqual({
      providerOptions: {
        gateway: { zeroDataRetention: true },
        openai: { store: false },
      },
    });
  });

  it('applies those options on the production eve model only', () => {
    const agent = readFileSync(join(repoRoot, 'agent/agent.ts'), 'utf8');
    const web = readFileSync(join(repoRoot, 'apps/web/src/lib/ai/zero-retention.ts'), 'utf8');
    expect(agent).toContain('providerZeroRetentionModelOptions');
    expect(agent).toContain('!isLocalSmokeEval && !isKnowledgeSkillEval');
    expect(web).toContain(`export const AI_ZERO_RETENTION_ENV = '${AI_ZERO_RETENTION_ENV}'`);
  });
});
