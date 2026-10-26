import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  coverageReport,
  LEDGER_PATH,
  LEVELS,
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

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const args = process.argv.slice(2);
    const merge = args[0] === '--merge';
    assert.ok(
      merge ? args.length === 3 : args.length <= 1 && !args[0]?.startsWith('-'),
      'usage: node scripts/correction-classifier.mjs [ledger.json] | --merge <sha|origin/main> <sha|origin/main>',
    );
    const path = merge ? resolve(LEDGER_PATH) : (args[0] ?? resolve(ROOT, LEDGER_PATH));
    const original = readFileSync(path, 'utf8');
    let result;
    if (merge) {
      const receipts = classifyLedger(
        args
          .slice(1)
          .flatMap((ref) => JSON.parse(readSource(LEDGER_PATH, { root: process.cwd(), ref }))),
      );
      const retained = new Map();
      for (const receipt of receipts) {
        const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
        const source = new URL(receipt.source).href;
        const key = JSON.stringify([fingerprint, source]);
        const previous = retained.get(key);
        if (previous) {
          assert.deepEqual(
            { ...previous, fingerprint, source },
            { ...receipt, fingerprint, source },
            `conflicting merge receipt: ${fingerprint}`,
          );
        } else {
          retained.set(key, receipt);
        }
      }
      result = [...retained.values()];
    } else {
      result = classifyLedger(JSON.parse(original));
    }
    // Validate the entire ledger before writing; a repeat run preserves bytes.
    if (
      merge
        ? original !== `${JSON.stringify(result, null, 2)}\n`
        : JSON.stringify(JSON.parse(original)) !== JSON.stringify(result)
    ) {
      writeFileSync(path, `${JSON.stringify(result, null, 2)}\n`);
    }
    console.log(`correction-classifier: classified ${result.length} receipts`);
  } catch (error) {
    console.error(`correction-classifier: ${error.message}`);
    process.exitCode = 1;
  }
}
