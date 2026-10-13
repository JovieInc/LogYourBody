import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Gitleaks runs through the shared JovieInc/ci secret-scan workflow. Download,
// checksum and scanner fail-closed behavior is tested there
// (tests/test_secret_scan_workflow.py); this pins how LogYourBody calls it.
const workflow = readFileSync(
  new URL('../../../.github/workflows/security-scan.yml', import.meta.url),
  'utf8',
);
const job = workflow.split('\n  gitleaks:\n')[1]?.split('\n  dependency-review:')[0] ?? '';

describe('shared Gitleaks security gate', () => {
  it('calls the JovieInc/ci secret scan pinned to a full commit SHA', () => {
    expect(job).toMatch(
      /^ {4}uses: JovieInc\/ci\/\.github\/workflows\/secret-scan\.yml@[0-9a-f]{40}$/m,
    );
  });

  it('keeps the full-history scan and fails on findings', () => {
    expect(job).toMatch(/^ {6}full-history: true$/m);
    expect(job).not.toContain('fail-on-findings');
  });

  it('grants the scan read-only contents and nothing else', () => {
    expect(job).toMatch(/^ {4}permissions:\n {6}contents: read\n*$/m);
  });

  it('runs on main pushes and manual dispatch, with no clock', () => {
    expect(workflow).toMatch(/push:\n\s+branches: \[main\]/);
    expect(workflow).not.toContain('schedule:');
    expect(workflow).toContain('workflow_dispatch:');
  });
});
