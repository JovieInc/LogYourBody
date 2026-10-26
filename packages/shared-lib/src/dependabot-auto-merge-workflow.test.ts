import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const workflow = readFileSync(
  new URL('../../../.github/workflows/dependabot-auto-merge.yml', import.meta.url),
  'utf8',
);
const call = workflow.split('\n  call:\n')[1]?.split(/\n {2}\S/)[0] ?? '';

describe('Dependabot auto-merge caller', () => {
  it('grants the reusable workflow its required write permissions only on the caller job', () => {
    expect(workflow).toMatch(/^permissions: \{\}$/m);
    expect(call).toMatch(
      /^ {4}uses: JovieInc\/ci\/\.github\/workflows\/dependabot-auto-merge\.yml@main$/m,
    );
    const permissions = call.match(/^ {4}permissions:\n((?: {6}[^\n]+\n?)+)/m)?.[1];
    expect(permissions?.trim().split(/\n\s*/).sort()).toEqual([
      'contents: write',
      'pull-requests: write',
    ]);
  });

  it('limits the privileged caller to Dependabot and retains the queue certification label', () => {
    expect(call).toMatch(/^ {4}if: github\.actor == 'dependabot\[bot\]'$/m);
    expect(call).toContain("certification_labels: 'machine-certified'");
  });
});
