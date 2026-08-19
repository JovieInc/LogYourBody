import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

function readRepoFile(repoRelativePath: string): string {
  return readFileSync(join(repoRoot, repoRelativePath), 'utf8');
}

function listTopLevelNames(directory: string): string[] {
  if (!existsSync(directory)) {
    return [];
  }

  return readdirSync(directory);
}

describe('Vercel Eve gym dogfood scaffold', () => {
  const agentDir = join(repoRoot, 'agent');
  const agentSource = readRepoFile('agent/agent.ts');
  const agentReadme = readRepoFile('agent/README.md');
  const instructions = readRepoFile('agent/instructions.md');
  const skill = readRepoFile('agent/skills/private-dogfood-research.md');
  const gymPath = readRepoFile('docs/product/vercel-eve-gym-dogfood.md');
  const packageJson = JSON.parse(readRepoFile('package.json')) as {
    scripts?: Record<string, string>;
    engines?: { node?: string };
    dependencies?: Record<string, string>;
  };

  it('exports a defineAgent config and keeps side-effect slots empty', () => {
    expect(agentSource).toMatch(/import\s+\{\s*defineAgent\s*\}\s+from\s+'eve'/);
    expect(agentSource).toMatch(/export\s+default\s+defineAgent\(/);
    expect(agentSource).toMatch(/model:\s*'openai\/gpt-5\.4-mini'/);
    expect(agentSource).toMatch(/Vercel Eve/);
    expect(agentSource).toMatch(/not the Summer\/Jovie internal Eve persona/);

    const forbiddenSlots = [
      'tools',
      'channels',
      'connections',
      'schedules',
      'subagents',
      'hooks',
      'sandbox',
    ];

    expect(listTopLevelNames(agentDir).sort()).toEqual(
      ['README.md', 'agent.ts', 'instructions.md', 'skills'].sort(),
    );

    for (const slot of forbiddenSlots) {
      expect(existsSync(join(agentDir, slot))).toBe(false);
    }

    expect(statSync(join(agentDir, 'skills', 'private-dogfood-research.md')).isFile()).toBe(true);
  });

  it('documents Vercel Eve, the gym loop, and a human-reviewed issue gate', () => {
    const namingDocs = [agentReadme, gymPath, instructions, skill];

    for (const source of namingDocs) {
      expect(source).toMatch(/Vercel Eve/);
      expect(source).toMatch(/not/i);
      expect(source).toMatch(/Summer|internal Eve/i);
    }

    expect(gymPath).toMatch(/Open LYB on the personal iPhone/);
    expect(gymPath).toMatch(/local Vercel Eve agent/);
    expect(gymPath).toMatch(/Human review is the only gate to GitHub/);
    expect(gymPath).toMatch(/must not create GitHub issues/);
    expect(gymPath).toMatch(/Node 20/);
    expect(gymPath).toMatch(/Node 24/);

    expect(agentReadme).toMatch(/Node 20/);
    expect(agentReadme).toMatch(/Node 24/);
    expect(agentReadme).toMatch(/pnpm eve:dev/);
    expect(agentReadme).toMatch(/No Vercel project is created/);

    expect(instructions).toMatch(/must not file it/);
    expect(skill).toMatch(/\[observed\]/);
    expect(skill).toMatch(/\[inferred\]/);
    expect(skill).toMatch(/\[hypothesis\]/);
    expect(skill).toMatch(/The Vercel Eve agent does not create the issue/);
  });

  it('keeps local eve scripts without changing the Node 20 engine contract', () => {
    expect(packageJson.scripts?.['eve:info']).toBe('eve info');
    expect(packageJson.scripts?.['eve:build']).toBe('eve build');
    expect(packageJson.scripts?.['eve:dev']).toBe('eve dev');
    expect(packageJson.engines?.node).toBe('20.x');
    expect(packageJson.dependencies?.eve).toEqual(expect.any(String));
  });
});
