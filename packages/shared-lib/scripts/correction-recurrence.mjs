// Durable correction receipts are replayed by the existing main remediation intake.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { classifyCorrection, LEVELS } from './correction-classification.mjs';
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

function groupCorrections(receipts) {
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
    if (
      receipt.recurrence !== undefined &&
      (!Number.isSafeInteger(receipt.recurrence) || receipt.recurrence < 0)
    ) {
      throw new Error('invalid_correction_recurrence');
    }
    const { level } = classifyCorrection(receipt, false);
    if (!LEVELS.includes(level)) throw new Error('invalid_correction_level');
    const annotation = JSON.stringify({ level, guard: receipt.guard ?? null });
    if (!groups.has(fingerprint))
      groups.set(fingerprint, {
        fingerprint,
        level,
        guard: receipt.guard,
        annotation,
        sources: new Map(),
        declaredRepeats: 0,
      });
    const group = groups.get(fingerprint);
    if (group.annotation !== annotation)
      // Conflicting source receipts require explicit resolution.
      throw new Error(`conflicting coverage annotations: ${fingerprint}; existing sources: ${[...group.sources.keys()].join(', ')}; incoming source: ${source.href}; existing guard: ${group.guard?.path ?? '(none)'}; incoming guard: ${receipt.guard?.path ?? '(none)'}`);
    group.declaredRepeats = Math.max(group.declaredRepeats, receipt.recurrence ?? 0);
    group.sources.set(source.href, {
      correction: receipt.correction.trim(),
      mechanization: receipt.mechanization.trim(),
    });
  }
  return [...groups.values()]
    .sort((a, b) => a.fingerprint.localeCompare(b.fingerprint))
    .map((group) => ({
      ...group,
      repeatCount: Math.max(group.sources.size - 1, group.declaredRepeats),
    }));
}

function issuePlans(groups) {
  return groups
    .filter(({ repeatCount }) => repeatCount >= 1)
    .map(({ fingerprint, sources, level, repeatCount }) => {
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
        sources: [...sources.keys()].sort(),
        repeatCount,
        createIssueId: `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`,
        title: `Mechanize recurring correction: ${fingerprint}`,
        description: [
          `Fingerprint: ${fingerprint}`,
          `The same correction has ${sources.size} distinct receipts. Mechanization is mandatory (LYB-209).`,
          `Recurrence: ${repeatCount} repeats.`,
          ...(level === 'prose'
            ? [`Requested enforcement: ${level} -> ${LEVELS[LEVELS.indexOf(level) - 1]}`]
            : []),
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
          '- Follow docs/engineering/correction-mechanization.md: warn on existing violations with a shrink-only baseline; fail new violations immediately.',
          '- Demonstrate a regression test that fails without the guard and passes with it.',
          '- Run the relevant checks and preserve all existing quality and security gates.',
          '- Leave the PR ready for the existing automatic merge queue after exact-head CI passes; no extra approval label.',
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

export function planCorrectionIssues(receipts) {
  return issuePlans(groupCorrections(receipts));
}

// A supplied Git snapshot distinguishes a new correction after a retained guard
// from historical receipts being replayed or promoted to a guard in this change.
export function scanCorrectionRecurrence(receipts, { previousReceipts } = {}) {
  const groups = groupCorrections(receipts);
  const previous =
    previousReceipts === undefined
      ? null
      : new Map(groupCorrections(previousReceipts).map((group) => [group.fingerprint, group]));
  const guardFailures = [];
  const candidates = [];
  for (const group of groups) {
    const before = previous?.get(group.fingerprint);
    const guarded = previous ? before : group;
    const sources = [...group.sources.keys()]
      .filter((source) => !before?.sources.has(source))
      .sort();
    if (before)
      group.repeatCount = Math.max(group.repeatCount, before.repeatCount + sources.length);
    const recurring =
      group.repeatCount > (before?.repeatCount ?? 0) || (before && sources.length > 0);
    if (guarded?.guard && ['codebase', 'static'].includes(guarded.level) && recurring) {
      guardFailures.push({ fingerprint: group.fingerprint, guard: guarded.guard, sources });
    } else if (!group.guard) {
      candidates.push(group);
    }
  }
  return {
    plans: issuePlans(candidates),
    guardFailures,
    recurrence: groups.map(({ fingerprint, repeatCount }) => ({ fingerprint, repeatCount })),
  };
}

async function processRecurrence({ receipts, previousReceipts, dryRun = true, env, fetchImpl }) {
  let scan;
  try {
    scan = scanCorrectionRecurrence(receipts, { previousReceipts });
  } catch (error) {
    return { ok: false, reason: `correction_ledger_invalid: ${error.message}` };
  }
  const { plans, guardFailures } = scan;
  const status = {
    ...scan,
    ok: !guardFailures.length,
    ...(guardFailures.length ? { reason: 'correction_guard_failure' } : {}),
  };
  if (!plans.length)
    return {
      ...status,
      action: guardFailures.length ? 'guard_failure' : 'skip',
      ...(!guardFailures.length ? { reason: 'no_recurrence' } : {}),
    };
  if (dryRun) return { ...status, action: guardFailures.length ? 'guard_failure' : 'dry_run' };
  const team = await findTeamIdByKey({
    teamKey: LYB_TEAM_KEY,
    apiKey: env.LINEAR_API_KEY,
    fetchImpl,
  });
  if (!team.ok) return { ...status, ...team };
  const issues = [];
  for (const plan of plans) {
    const request = {
      ...plan,
      teamId: team.id,
      apiKey: env.LINEAR_API_KEY,
      fetchImpl,
      reopenTerminal: (issue) => {
        const description = String(issue.description ?? '');
        const repeats = Number(
          /Recurrence: (\d+) repeats\./.exec(description)?.[1] ??
            Number(/has (\d+) distinct receipts/.exec(description)?.[1]) - 1,
        );
        return (
          plan.sources.some((source) => !description.includes(`- ${source}\n`)) ||
          plan.repeatCount > repeats
        );
      },
    };
    let result = await upsertLinearIssue(request);
    // Recover a concurrent create or a committed create whose reply was lost.
    if (!result.ok && result.reason?.startsWith('linear_create')) {
      result = await upsertLinearIssue(request);
    }
    issues.push(result);
  }
  return {
    ...status,
    ok: status.ok && issues.every((issue) => issue.ok),
    action: guardFailures.length ? 'guard_failure' : 'recurrence',
    issues,
    reason: status.reason ?? issues.find((issue) => !issue.ok)?.reason,
  };
}

export async function runCorrectionRecurrence({
  env = process.env,
  eventName,
  event = {},
  ledgerPath = env.CORRECTION_LEDGER_PATH || CORRECTION_LEDGER,
  receipts,
  previousReceipts,
  dryRun = true,
  fetchImpl = fetch,
} = {}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled' };
  // Admit the same verified main-only event sources as the remediation router.
  if (!detectorFromGithubEvent(eventName, event, env)?.provenance) {
    return { ok: true, action: 'skip', reason: 'no_verified_main_source' };
  }
  try {
    receipts ??= JSON.parse(readFileSync(ledgerPath, 'utf8'));
  } catch (error) {
    return { ok: false, reason: `correction_ledger_invalid: ${error.message}` };
  }
  return processRecurrence({ receipts, previousReceipts, dryRun, env, fetchImpl });
}

export async function runRecurrenceCli(argv, { env = process.env, fetchImpl = fetch } = {}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled' };
  let ledgerPath = env.CORRECTION_LEDGER_PATH || CORRECTION_LEDGER;
  let previousReceipts;
  let dryRun = true;
  for (let index = 0; index < argv.length; index++) {
    const option = argv[index];
    if (option === '--apply') dryRun = false;
    else if (option === '--ledger' && argv[index + 1]) ledgerPath = argv[++index];
    else if (option === '--base-ref' && /^(?:[a-f0-9]{40}|origin\/main)$/.test(argv[index + 1])) {
      previousReceipts = JSON.parse(
        execFileSync('git', ['show', `${argv[++index]}:packages/shared-lib/corrections.json`], {
          cwd: fileURLToPath(new URL('../../..', import.meta.url)),
          encoding: 'utf8',
        }),
      );
    } else
      throw new Error(
        'usage: correction-recurrence.mjs [--ledger <path>] [--base-ref <sha|origin/main>] [--apply]',
      );
  }
  return processRecurrence({
    receipts: JSON.parse(readFileSync(ledgerPath, 'utf8')),
    previousReceipts,
    dryRun,
    env,
    fetchImpl,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const result = await runRecurrenceCli(process.argv.slice(2));
    console.log(JSON.stringify(result, null, 2));
    if (!result.ok) process.exitCode = 1;
  } catch (error) {
    console.error(`Correction recurrence failed: ${error.message}`);
    process.exitCode = 1;
  }
}
