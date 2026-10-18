// Durable correction receipts are replayed by the existing main remediation intake.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import {
  findTeamIdByKey,
  LYB_TEAM_KEY,
  upsertLinearIssue,
} from '../../../.github/scripts/lib/linear-issue-intake.mjs';
import {
  detectorFromGithubEvent,
  remediationIntakeDisabled,
} from '../../../.github/scripts/remediation-signal.mjs';

export const CORRECTION_LEDGER = new URL('../corrections.json', import.meta.url);

export function planCorrectionIssues(receipts) {
  if (!Array.isArray(receipts)) throw new Error('correction_ledger_must_be_an_array');
  const groups = new Map();
  for (const receipt of receipts) {
    const fingerprint =
      typeof receipt?.fingerprint === 'string'
        ? receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-')
        : '';
    if (
      !/^[a-z0-9][a-z0-9._:-]{0,159}$/.test(fingerprint) ||
      typeof receipt?.correction !== 'string' ||
      !receipt.correction.trim() ||
      typeof receipt?.mechanization !== 'string' ||
      !receipt.mechanization.trim()
    ) {
      throw new Error('invalid_correction_receipt');
    }
    const source = new URL(receipt.source);
    if (source.protocol !== 'https:' || source.username || source.password) {
      throw new Error('invalid_correction_source');
    }
    if (!groups.has(fingerprint)) groups.set(fingerprint, new Map());
    groups.get(fingerprint).set(source.href, {
      correction: receipt.correction.trim(),
      mechanization: receipt.mechanization.trim(),
    });
  }
  return [...groups]
    .sort(([a], [b]) => a.localeCompare(b))
    .filter(([, sources]) => sources.size >= 2)
    .map(([fingerprint, sources]) => {
      const hash = createHash('sha256')
        .update(`LYB:correction-recurrence:v1:${fingerprint}`)
        .digest();
      const label = `remediation:correction-${hash.toString('hex')}`;
      // Linear accepts a caller-supplied UUID v4. Stable bits prevent racing
      // main CI, Deploy and scheduled intakes from creating separate issues.
      hash[6] = (hash[6] & 0x0f) | 0x40;
      hash[8] = (hash[8] & 0x3f) | 0x80;
      const hex = hash.subarray(0, 16).toString('hex');
      return {
        label,
        createIssueId: `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`,
        title: `Mechanize recurring correction: ${fingerprint}`,
        description: [
          `Fingerprint: ${fingerprint}`,
          `The same correction has ${sources.size} distinct receipts. Mechanization is mandatory (LYB-209).`,
          '',
          '## Correction evidence and proposed guards',
          ...[...sources]
            .sort(([a], [b]) => a.localeCompare(b))
            .flatMap(([source, receipt]) => [
              `- ${source}`,
              `  Correction: ${receipt.correction}`,
              `  Proposed guard: ${receipt.mechanization}`,
            ]),
          '',
          '## Acceptance criteria',
          '- Reproduce the repeated failure from the linked correction receipts.',
          '- Implement the smallest deterministic guard, lint, test, or automation that prevents recurrence.',
          '- Demonstrate a regression test that fails without the guard and passes with it.',
          '- Run the relevant checks and preserve all existing quality and security gates.',
          '',
          `Label: ${label}`,
          'Repository: JovieInc/LogYourBody',
        ].join('\n'),
        priority: 2,
        createStateName: 'Todo',
        createLabelNames: ['agent-ready'],
      };
    });
}

export async function runCorrectionRecurrence({
  env = process.env,
  eventName,
  event = {},
  ledgerPath = env.CORRECTION_LEDGER_PATH || CORRECTION_LEDGER,
  receipts,
  fetchImpl = fetch,
} = {}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled' };
  // Admit the same verified main-only event sources as the remediation router.
  if (!detectorFromGithubEvent(eventName, event, env)?.provenance) {
    return { ok: true, action: 'skip', reason: 'no_verified_main_source' };
  }
  let plans;
  try {
    plans = planCorrectionIssues(receipts ?? JSON.parse(readFileSync(ledgerPath, 'utf8')));
  } catch (error) {
    return { ok: false, reason: `correction_ledger_invalid: ${error.message}` };
  }
  if (!plans.length) return { ok: true, action: 'skip', reason: 'no_recurrence' };
  const team = await findTeamIdByKey({
    teamKey: LYB_TEAM_KEY,
    apiKey: env.LINEAR_API_KEY,
    fetchImpl,
  });
  if (!team.ok) return team;
  const issues = [];
  for (const plan of plans) {
    const request = { ...plan, teamId: team.id, apiKey: env.LINEAR_API_KEY, fetchImpl };
    let result = await upsertLinearIssue(request);
    // Recover a concurrent create or a committed create whose reply was lost.
    if (!result.ok && result.reason?.startsWith('linear_create')) {
      result = await upsertLinearIssue(request);
    }
    issues.push(result);
  }
  return {
    ok: issues.every((issue) => issue.ok),
    action: 'recurrence',
    issues,
    reason: issues.find((issue) => !issue.ok)?.reason,
  };
}
