import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  assertLedgerMergeReady,
  assertNoRegression,
  coverageReport,
  guardCoverageReport,
  LEDGER_PATH,
  LEVELS,
  mergeCorrectionLedgers,
  readGitMergeLedgers,
  readSource,
  ROOT,
} from '../packages/shared-lib/scripts/correction-coverage.mjs';

const levels = LEVELS.filter((level) => level !== 'unclassified');
const rules = [
  {
    id: 'type-or-schema',
    level: 'codebase',
    pattern: /\b(?:types?|typed|schemas?|structs?|enums?|interfaces?)\b/iu,
  },
  { id: 'code-prevention', level: 'codebase' },
  {
    id: 'file-pattern-or-string',
    level: 'static',
    pattern:
      /[\w./*-]+\.[a-z][a-z0-9]*(?=$|[\s.,;:'"`)\]])|[\w./-]+\*[\w./*?-]*|[?*][\w./*?-]+|(?:^|[\s([{])(?:`[^`\n]+`|"[^"\n]+"|'[^'\n]+')/iu,
  },
  { id: 'ci-invariant', level: 'static' },
  { id: 'prose-guidance', level: 'prose' },
  { id: 'human-judgment', level: 'human' },
];

function objectFields(value, allowed, location) {
  assert.ok(
    value && typeof value === 'object' && !Array.isArray(value),
    `${location}: expected an object`,
  );
  for (const field of Object.keys(value)) {
    assert.ok(allowed.includes(field), `${location}: unknown field: ${field}`);
  }
}

function nonblank(value, location) {
  assert.ok(typeof value === 'string' && value.trim(), `${location}: expected a nonblank string`);
}

function validateReceipt(receipt, index) {
  const location = `entry ${index + 1}`;
  objectFields(
    receipt,
    [
      'fingerprint',
      'correction',
      'source',
      'mechanization',
      'classification',
      'level',
      'ruleId',
      'guard',
      'proseOnlyReason',
    ],
    location,
  );
  for (const field of ['fingerprint', 'correction', 'source', 'mechanization']) {
    nonblank(receipt[field], `${location}.${field}`);
  }
  objectFields(receipt.classification, levels, `${location}.classification`);
  for (const [level, assessment] of Object.entries(receipt.classification)) {
    objectFields(assessment, ['feasible', 'rationale'], `${location}.classification.${level}`);
    assert.equal(
      typeof assessment.feasible,
      'boolean',
      `${location}.classification.${level}.feasible: expected a boolean assessment`,
    );
    nonblank(assessment.rationale, `${location}.classification.${level}.rationale`);
  }
  if (receipt.level !== undefined) {
    assert.ok(levels.includes(receipt.level), `${location}: unknown level: ${receipt.level}`);
  }
  if (receipt.ruleId !== undefined) {
    const rule = rules.find(({ id }) => id === receipt.ruleId);
    assert.ok(rule, `${location}: unknown ruleId: ${receipt.ruleId}`);
    assert.equal(rule.level, receipt.level, `${location}: ruleId must match the saved level`);
  }
  if (receipt.guard !== undefined) {
    objectFields(receipt.guard, ['path', 'anchor', 'ratchet'], `${location}.guard`);
    nonblank(receipt.guard.path, `${location}.guard.path`);
    nonblank(receipt.guard.anchor, `${location}.guard.anchor`);
    if (receipt.guard.ratchet !== undefined) {
      objectFields(receipt.guard.ratchet, ['baseline'], `${location}.guard.ratchet`);
      nonblank(receipt.guard.ratchet.baseline, `${location}.guard.ratchet.baseline`);
    }
  }
  if (receipt.proseOnlyReason !== undefined) {
    nonblank(receipt.proseOnlyReason, `${location}.proseOnlyReason`);
  }
}

export function classifyLedger(receipts) {
  assert.ok(Array.isArray(receipts), 'ledger must be an array of LYB-204 correction receipts');
  receipts.forEach(validateReceipt);
  // The merged schema's reviewed feasibility assessments own eligibility.
  // Reuse its ordering and duplicate-receipt validation rather than guessing
  // whether an incidental keyword makes a full invariant mechanizable.
  const report = coverageReport(
    receipts.map(({ level: _level, ...receipt }) => receipt),
    () => '',
    { requireClassification: true },
  );
  const selections = new Map(
    report.rules.map((entry) => {
      const text = [entry.rationale, ...entry.receipts.map(({ correction }) => correction)].join(
        '\n',
      );
      const rule = rules.find(
        ({ level, pattern }) => level === entry.level && (!pattern || pattern.test(text)),
      );
      return [entry.fingerprint, { level: entry.level, ruleId: rule.id }];
    }),
  );
  return receipts.map((receipt) => {
    const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
    const selection = selections.get(fingerprint);
    assert.ok(
      receipt.level === undefined ||
        levels.indexOf(selection.level) <= levels.indexOf(receipt.level),
      `refusing to downgrade ${fingerprint}: existing level ${receipt.level}, selected ${selection.level}`,
    );
    return { ...receipt, ...selection };
  });
}

function mergeLedgers(left, right) {
  // Classify the complete union before deduplication so incompatible guards,
  // missing assessments and attempted downgrades still fail closed.
  assert.ok(Array.isArray(left) && Array.isArray(right), 'merge ledgers must be arrays');
  const merged = new Map();
  for (const receipt of classifyLedger([...left, ...right])) {
    const normalized = {
      ...receipt,
      fingerprint: receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-'),
      source: new URL(receipt.source).href,
    };
    const key = JSON.stringify([normalized.fingerprint, normalized.source]);
    if (merged.has(key)) {
      assert.deepEqual(merged.get(key), normalized, `conflicting merge receipt: ${key}`);
    } else {
      merged.set(key, normalized);
    }
  }
  return [...merged.values()];
}

function readGitSources(root, objects, execute) {
  for (const object of objects) {
    assert.doesNotMatch(object, /[\r\n\0]/u, 'invalid Git source request');
  }
  // Only regular indexed files can provide staged guard evidence.
  const regularGuards = new Set(
    execute(
      'git',
      [
        '-C',
        root,
        '--literal-pathspecs',
        'ls-files',
        '--stage',
        '-z',
        '--',
        ...objects.filter((object) => object.startsWith(':0:')).map((object) => object.slice(3)),
      ],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    )
      .split('\0')
      .filter((entry) => /^100(?:644|755) [a-f0-9]+ 0\t/u.test(entry))
      .map((entry) => entry.slice(entry.indexOf('\t') + 1)),
  );
  const output = execute('git', ['-C', root, 'cat-file', '--batch'], {
    input: objects.map((object) => `${object}\n`).join(''),
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  let offset = 0;
  return new Map(
    objects.map((object) => {
      const end = output.indexOf(10, offset);
      const header = output.toString('utf8', offset, end);
      offset = end + 1;
      if (header.endsWith(' missing')) return [object, ''];
      const match = /^[a-f0-9]+ blob (\d+)$/u.exec(header);
      assert.ok(match, `invalid Git source response: ${header}`);
      const size = Number(match[1]);
      const source = output.toString('utf8', offset, offset + size);
      offset += size + 1;
      return [
        object,
        object.startsWith(':0:') && !regularGuards.has(object.slice(3)) ? '' : source,
      ];
    }),
  );
}

// Keep the repair command reusable without starting Node or exiting its caller.
export function runClassifier(args, logger = console, execute = execFileSync) {
  try {
    const resolvingMerge = args[0] === '--resolve-merge';
    const checkingMerge = args[0] === '--check-merge';
    const stagingMerge = resolvingMerge && args[2] === '--stage';
    assert.ok(
      resolvingMerge || checkingMerge
        ? (args.length === 2 || (args.length === 3 && stagingMerge)) && !args[1].startsWith('-')
        : (args.length <= 1 ||
            (args.length === 3 && args[1] === '--merge' && !args[2].startsWith('-'))) &&
            !args[0]?.startsWith('-'),
      'usage: node scripts/correction-classifier.mjs [ledger.json [--merge other.json]] | --resolve-merge repository [--stage] | --check-merge repository',
    );
    let path;
    let result;
    let stageResolution;
    if (resolvingMerge || checkingMerge) {
      const git = (...gitArgs) =>
        execute('git', ['-C', args[1], ...gitArgs], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
        });
      // Require both immutable merge parents before resolving any ledger.
      const [root, ...parents] = git('rev-parse', '--show-toplevel', 'HEAD', 'MERGE_HEAD')
        .trim()
        .split('\n');
      path = resolve(root, LEDGER_PATH);
      const verifyMerge = (receipts) => {
        assert.deepEqual(
          receipts,
          classifyLedger(receipts),
          'staged merge ledger must be classified',
        );
        const baselines = parents.map((ref) => ({
          ref,
          receipts: JSON.parse(git('show', `${ref}:${LEDGER_PATH}`)),
        }));
        // Batch guard blobs per verification; never cache the mutable index across retries.
        const objects = [
          ...new Set(
            [{ ref: ':0', receipts }, ...baselines].flatMap(({ ref, receipts }) =>
              receipts.filter(({ guard }) => guard).map(({ guard }) => `${ref}:${guard.path}`),
            ),
          ),
        ];
        const sources = readGitSources(root, objects, execute);
        const current = guardCoverageReport(receipts, (guard) => sources.get(`:0:${guard}`), {
          requireClassification: true,
        });
        for (const { ref, receipts } of baselines) {
          const baseline = coverageReport(receipts, (guard) => sources.get(`${ref}:${guard}`));
          assertNoRegression(current, baseline);
        }
      };
      // Verify the whole merge is conflict-free, including staged retries.
      assertLedgerMergeReady(root);
      // A retry after explicit staging verifies the index without overwriting local edits.
      if (checkingMerge || !git('ls-files', '--unmerged', '--', LEDGER_PATH)) {
        const staged = git('show', `:0:${LEDGER_PATH}`);
        verifyMerge(JSON.parse(staged));
        assert.equal(
          readSource(LEDGER_PATH, { root }),
          staged,
          'staged retry refuses unstaged ledger edits; review and stage them explicitly',
        );
        logger.log('correction-classifier: verified staged ledger against both merge parents');
        return 0;
      }
      const working = readSource(LEDGER_PATH, { root }); // Refuse symlinked output.
      if (!/^(?:<+|\|+|=+|>+)(?: |$)/m.test(working)) {
        // Preserve manually resolved receipts instead of rebuilding from the parents.
        result = classifyLedger(JSON.parse(working));
        if (!stagingMerge) verifyMerge(result);
      } else {
        // Reuse the coverage tool's three-way policy rather than a second resolver.
        // Classify snapshots first so derived metadata cannot look like concurrent edits.
        // Normalize identical parent replays with the existing union policy.
        const stages = readGitMergeLedgers(root).map((rows) => mergeLedgers(rows, []));
        // Batch the staged union's guards too; repeated receipts must not spawn Git.
        const sources = stagingMerge
          ? readGitSources(
              root,
              [
                ...new Set(
                  stages
                    .flat()
                    .filter(({ guard }) => guard)
                    .map(({ guard }) => `:0:${guard.path}`),
                ),
              ],
              execute,
            )
          : null;
        result = classifyLedger(
          // Keep incoming order, then append branch-only receipts so future main
          // prepends do not collide with the same branch receipt on every repair.
          mergeCorrectionLedgers(stages[0], stages[2], stages[1], (guard) =>
            stagingMerge ? sources.get(`:0:${guard}`) : readSource(guard, { root }),
          ),
        );
      }
      if (stagingMerge) {
        // Validate staged guards and both parents before writing or staging anything.
        verifyMerge(result);
        stageResolution = () => git('add', '--', LEDGER_PATH);
      }
    } else {
      path = args[0] ?? resolve(ROOT, LEDGER_PATH);
      const receipts = JSON.parse(readFileSync(path, 'utf8'));
      result =
        args.length === 3
          ? mergeLedgers(receipts, JSON.parse(readFileSync(args[2], 'utf8')))
          : classifyLedger(receipts);
    }
    const original = readFileSync(path, 'utf8');
    const formatted = `${JSON.stringify(result, null, 2)}\n`;
    // Validate the entire ledger before writing; a repeat run preserves bytes.
    if (
      resolvingMerge
        ? original !== formatted
        : JSON.stringify(JSON.parse(original)) !== JSON.stringify(result)
    ) {
      writeFileSync(path, formatted);
    }
    stageResolution?.();
    logger.log(`correction-classifier: classified ${result.length} receipts`);
    return 0;
  } catch (error) {
    logger.error(`correction-classifier: ${error.message}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = runClassifier(process.argv.slice(2));
}
