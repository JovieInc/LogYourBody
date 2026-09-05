import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const workflow = readFileSync(`${root}/.github/workflows/deploy.yml`, 'utf8');
const summaryJob = workflow.split('\n  deploy-summary:\n')[1];
const script = summaryJob
  .split('        run: |\n')[1]
  .split('\n')
  .map((line) => line.replace(/^ {10}/, ''))
  .join('\n');

type Inputs = {
  detect?: string;
  webChanged?: string;
  iosChanged?: string;
  web?: string;
  ios?: string;
};
function runSummary(inputs: Inputs = {}) {
  const values = {
    'needs.detect-changes.result': inputs.detect ?? 'success',
    'needs.detect-changes.outputs.web': inputs.webChanged ?? 'true',
    'needs.detect-changes.outputs.ios': inputs.iosChanged ?? 'false',
    'needs.web.result': inputs.web ?? 'success',
    'needs.ios-beta.result': inputs.ios ?? 'skipped',
  };
  const directory = mkdtempSync(`${tmpdir()}/lyb-deploy-summary-`);
  const summaryPath = `${directory}/summary.md`;
  try {
    // Render only the workflow's known dependency expressions, exactly as Actions does.
    const rendered = script.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_, key: string) => {
      if (!(key in values)) throw new Error(`Unexpected workflow expression: ${key}`);
      return values[key as keyof typeof values];
    });
    const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', rendered], {
      encoding: 'utf8',
      timeout: 10_000,
      env: { ...process.env, GITHUB_STEP_SUMMARY: summaryPath },
    });
    return {
      status: result.status,
      stderr: result.stderr,
      summary: readFileSync(summaryPath, 'utf8'),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

describe('Deploy Summary dependency propagation', () => {
  it('rejects the observed failed Web deploy even when disabled iOS is skipped', () => {
    expect(runSummary({ web: 'failure' }).status).toBe(1);
  });

  it('accepts successful selected web and disabled iOS', () => {
    expect(runSummary().status).toBe(0);
  });

  it('accepts genuinely unselected web and disabled iOS', () => {
    const result = runSummary({ webChanged: 'false', web: 'skipped', iosChanged: 'true' });
    expect(result.status).toBe(0);
    expect(result.summary).toContain('skipped');
    expect(result.summary).toContain('disabled');
  });

  it.each(['failure', 'cancelled', 'skipped', 'unknown', ''])(
    'rejects detection result %s',
    (detect) => {
      expect(runSummary({ detect, webChanged: '', iosChanged: '', web: 'skipped' }).status).toBe(1);
    },
  );

  it.each(['failure', 'cancelled', 'skipped', 'unknown', ''])(
    'rejects selected web result %s',
    (web) => {
      expect(runSummary({ web }).status).toBe(1);
    },
  );

  it.each(['failure', 'cancelled', 'success', 'unknown', ''])(
    'rejects unselected web result %s',
    (web) => {
      expect(runSummary({ webChanged: 'false', web }).status).toBe(1);
    },
  );

  it.each(['failure', 'cancelled', 'success', 'unknown', ''])(
    'rejects disabled iOS result %s',
    (ios) => {
      expect(runSummary({ ios }).status).toBe(1);
    },
  );

  it.each(['', 'unknown'])('rejects missing or invalid detection output %s', (flag) => {
    expect(runSummary({ webChanged: flag }).status).toBe(1);
    expect(runSummary({ iosChanged: flag }).status).toBe(1);
  });

  it('keeps unconditional summary dependency wiring and the explicit disabled-iOS policy aligned', () => {
    expect(summaryJob).toContain('if: always()');
    expect(summaryJob).toContain('needs: [detect-changes, web, ios-beta]');
    expect(workflow).toContain(
      "if: needs.detect-changes.outputs.ios == 'true' && false # Enable when ready",
    );
  });
});
