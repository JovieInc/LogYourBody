import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, mkdirSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { generateReport, parseInput, run, MAX_INPUT_BYTES } from './growth-report.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const now = new Date('2026-10-16T12:00:00Z');
function fixture() {
  const input = {
    schema_version: 1,
    environment: 'production',
    source_revision: 'a'.repeat(40),
    as_of: '2026-10-16T12:00:00Z',
    window: { from: '2026-09-01T00:00:00Z', to: '2026-09-02T00:00:00Z' },
    sources: [],
  };
  for (const [index, source] of ['statsig', 'core_data_neon', 'revenuecat'].entries()) {
    input.sources.push({
      source,
      environment: 'production',
      receipt_sha256: String(index).repeat(64),
      ...input.window,
      watermark: input.as_of,
      commissioned: true,
      reconciled: true,
      exclusions: ['sandbox', 'testflight', 'qa', 'synthetic', 'duplicates'],
      metrics:
        source === 'statsig'
          ? { onboarding_started: 10, first_insight_rendered: 8 }
          : source === 'core_data_neon'
            ? {
                activation_v1: { numerator: 8, denominator: 10, missing: 0 },
                d7_retention_v1: { numerator: 4, denominator: 8, missing: 0 },
                d30_retention_v1: { numerator: 2, denominator: 8, missing: 0 },
              }
            : {
                supported_charge_count: 2,
                observed_gross_purchase_usd: 19.98,
                supported_observed_mrr_usd: 9.99,
              },
    });
  }
  return input;
}
function row(report, metric) {
  return report.metrics.find((item) => item.metric === metric);
}
function rejects(change) {
  const input = fixture();
  change(input);
  assert.throws(() => generateReport(input, now), /^Error: Invalid private growth evidence$/);
}

test('composes qualified aggregates without manufacturing conversions, net revenue or outcomes', () => {
  const input = fixture();
  const report = generateReport(input, now);
  assert.equal(report.visibility, 'private_operator_only');
  assert.equal(report.source_revision, input.source_revision);
  assert.deepEqual(report.window, input.window);
  assert.equal(row(report, 'first_insight_rendered').value, 8);
  assert.equal(row(report, 'first_insight_rendered').unit, 'anonymous_events');
  assert.equal(row(report, 'activation_v1').value, 0.8);
  assert.equal(row(report, 'd7_retention_v1').value, 0.5);
  assert.equal(row(report, 'd30_retention_v1').value, 0.25);
  assert.equal(row(report, 'observed_gross_purchase_usd').value, 19.98);
  assert.equal(row(report, 'supported_observed_mrr_usd').value, 9.99);
  assert.equal(row(report, 'supported_charge_count').unit, 'transactions');
  assert.ok(report.metrics.every((metric) => metric.status === 'qualified'));
  for (const key of [
    'qualified_coaching_activation',
    'first_insight_conversion',
    'trial_to_paid_conversion',
    'customer_outcomes',
  ]) {
    assert.deepEqual(report[key], { status: 'unknown', value: null });
  }
  assert.deepEqual(report.net_revenue_usd, { status: 'unreconciled', value: null });
  assert.deepEqual(report.refunds, { status: 'unreconciled', value: null });
  assert.equal(report.provider_commissioning, 'not_independently_verified');
  assert.equal(report.snapshot_status, 'current_as_of');
});

test('missing sources, metrics and null SQL money remain unknown; true zero is distinct', () => {
  const input = fixture();
  input.sources = [];
  assert.ok(
    generateReport(input, now).metrics.every(
      (item) => item.status === 'unknown' && item.value === null,
    ),
  );
  input.sources = fixture().sources;
  input.sources[0].metrics = { first_insight_rendered: 0 };
  input.sources[2].metrics.supported_observed_mrr_usd = null;
  const report = generateReport(input, now);
  assert.equal(row(report, 'onboarding_started').status, 'unknown');
  assert.equal(row(report, 'first_insight_rendered').value, 0);
  assert.equal(row(report, 'supported_observed_mrr_usd').value, null);
  assert.equal(row(report, 'supported_observed_mrr_usd').status, 'unknown');
});

test('preserves overlapping stale, unreconciled, uncommissioned and incomplete reasons', () => {
  const input = fixture();
  const source = input.sources[1];
  source.commissioned = false;
  source.reconciled = false;
  source.watermark = '2026-10-14T11:59:59Z';
  source.metrics.activation_v1.missing = 1;
  const result = row(generateReport(input, now), 'activation_v1');
  assert.deepEqual(result.issues, ['stale', 'uncommissioned', 'unreconciled', 'incomplete']);
  assert.equal(result.value, null);
  assert.deepEqual(result.observation, { numerator: 8, denominator: 10, missing: 1 });
  assert.equal(result.receipt_sha256, source.receipt_sha256);
  assert.ok(row(generateReport(input, now), 'd7_retention_v1').issues.includes('incomplete'));
});

test('uses exclusive cohort end and full D7/D30 observation windows, never partial rates', () => {
  const input = fixture();
  for (const [metric, days] of [
    ['activation_v1', 1],
    ['d7_retention_v1', 9],
    ['d30_retention_v1', 32],
  ]) {
    const end = Date.parse(input.window.to) + days * 86_400_000;
    input.as_of = new Date(end).toISOString().replace('.000Z', 'Z');
    for (const source of input.sources) source.watermark = input.as_of;
    input.sources[1].watermark = new Date(end - 1000).toISOString().replace('.000Z', 'Z');
    let result = row(generateReport(input, now), metric);
    assert.ok(result.issues.includes('immature'));
    assert.equal(result.value, null);
    input.sources[1].watermark = input.as_of;
    result = row(generateReport(input, now), metric);
    assert.equal(result.status, 'qualified');
  }
});

test('freshness and coverage boundaries are explicit', () => {
  const input = fixture();
  input.sources[0].watermark = '2026-10-15T12:00:00Z';
  assert.equal(row(generateReport(input, now), 'first_insight_rendered').status, 'qualified');
  input.sources[0].watermark = '2026-09-01T23:59:59Z';
  input.as_of = input.window.to;
  input.sources[1].watermark = input.as_of;
  input.sources[2].watermark = input.as_of;
  assert.equal(row(generateReport(input, now), 'first_insight_rendered').status, 'stale');
  assert.equal(generateReport(input, now).snapshot_status, 'stale');
});

test('rejects sensitive and unknown fields at every nesting level without echoing them', () => {
  const sensitive = [
    'email',
    'user_id',
    'weight',
    'body_fat',
    'token',
    'notes',
    'transcript',
    'url',
    'surprise',
  ];
  for (const key of sensitive) {
    for (const target of [
      (x) => x,
      (x) => x.window,
      (x) => x.sources[0],
      (x) => x.sources[0].metrics,
      (x) => x.sources[1].metrics.activation_v1,
    ]) {
      rejects((input) => {
        target(input)[key] = 'private-value';
      });
    }
  }
  rejects((input) => {
    input.sources[0].metrics.onboarding_body_score_calculation_succeeded = 8;
  });
  rejects((input) => {
    input.sources[0].metrics.onboarding_step_advanced = 8;
  });
  rejects((input) => {
    input.sources[0].metrics.trial_start = 8;
  });
  rejects((input) => {
    input.sources[0].metrics.purchase_success = 8;
  });
  rejects((input) => {
    input.sources[2].metrics.refund_or_reversal_event_count = 8;
  });
  rejects((input) => {
    input.sources[0].metrics.activation_v1 = { numerator: 1, denominator: 1, missing: 0 };
  });
});

test('rejects duplicate JSON keys before overwriting evidence, including escaped key aliases', () => {
  for (const text of [
    '{"environment":"sandbox","environment":"production"}',
    '{"sources":[{"metrics":{"first_insight_rendered":10,"first_insight_rendered":20}}]}',
    '{"metrics":{"weight":70,"\\u0077eight":80}}',
  ])
    assert.throws(() => parseInput(text), /Invalid private growth evidence/);
  const value = { nested: [{ key: 'punctuation { [ : , } ] and "quotes"' }], key: 'elsewhere' };
  assert.deepEqual(parseInput(JSON.stringify(value)), value);
});

test('rejects malformed schema, provenance, sandbox, duplicate snapshots and reused receipts', () => {
  for (const value of [null, [], 1, 'private']) assert.throws(() => generateReport(value, now));
  for (const value of [0, 2, '1', null])
    rejects((x) => {
      x.schema_version = value;
    });
  for (const value of ['sandbox', 'testflight', 'qa', null]) {
    rejects((x) => {
      x.environment = value;
    });
    rejects((x) => {
      x.sources[0].environment = value;
    });
  }
  for (const key of Object.keys(fixture()))
    rejects((x) => {
      delete x[key];
    });
  for (const key of Object.keys(fixture().sources[0]))
    rejects((x) => {
      delete x.sources[0][key];
    });
  for (const value of ['private-value', '', null]) {
    rejects((x) => {
      x.source_revision = value;
    });
    rejects((x) => {
      x.sources[0].receipt_sha256 = value;
    });
  }
  rejects((x) => {
    x.sources = {};
  });
  rejects((x) => {
    x.sources.push(x.sources[0]);
  });
  rejects((x) => {
    x.sources[1] = x.sources[0];
  });
  rejects((x) => {
    x.sources[1].receipt_sha256 = x.sources[0].receipt_sha256;
  });
  rejects((x) => {
    x.sources[0].source = 'unknown-provider';
  });
  rejects((x) => {
    x.sources[0].metrics = [];
  });
  rejects((x) => {
    x.sources[0].commissioned = 'true';
  });
  rejects((x) => {
    x.sources[0].reconciled = 1;
  });
  rejects((x) => {
    x.sources[0].exclusions.pop();
  });
  rejects((x) => {
    x.sources[0].exclusions[0] = 'duplicates';
  });
  rejects((x) => {
    x.sources[0].exclusions = 'sandbox';
  });
});

test('rejects impossible, non-UTC, future, inverted, mismatched and unbounded windows', () => {
  for (const value of [
    '2026-02-30T00:00:00Z',
    '2026-09-01',
    '2026-09-01T00:00:00+00:00',
    null,
    'private-value',
  ]) {
    rejects((x) => {
      x.window.from = value;
    });
  }
  rejects((x) => {
    x.as_of = '2026-10-17T00:00:00Z';
  });
  rejects((x) => {
    x.window.to = x.window.from;
  });
  rejects((x) => {
    x.window.from = '2026-09-03T00:00:00Z';
  });
  rejects((x) => {
    x.window.to = '2026-10-17T00:00:00Z';
  });
  rejects((x) => {
    x.window.from = '2026-01-01T00:00:00Z';
  });
  rejects((x) => {
    x.sources[0].from = '2026-09-01T01:00:00Z';
  });
  rejects((x) => {
    x.sources[0].to = '2026-09-01T01:00:00Z';
  });
  rejects((x) => {
    x.sources[0].watermark = '2026-10-17T00:00:00Z';
  });
});

test('rejects invalid denominators, missing coverage, nonfinite values and negative or excessive money', () => {
  for (const key of ['numerator', 'denominator', 'missing']) {
    for (const value of [-1, 0.5, NaN, Infinity, '1', null, 10_000_001]) {
      rejects((x) => {
        x.sources[1].metrics.activation_v1[key] = value;
      });
    }
    rejects((x) => {
      delete x.sources[1].metrics.activation_v1[key];
    });
  }
  rejects((x) => {
    x.sources[1].metrics.activation_v1.denominator = 0;
  });
  rejects((x) => {
    x.sources[1].metrics.activation_v1.numerator = 11;
  });
  rejects((x) => {
    x.sources[1].metrics.activation_v1.missing = 3;
  });
  rejects((x) => {
    x.sources[1].metrics.d7_retention_v1.denominator = 10;
  });
  rejects((x) => {
    delete x.sources[1].metrics.activation_v1;
  });
  for (const value of [-1, NaN, Infinity, '9.99', {}, 1_000_000_001]) {
    rejects((x) => {
      x.sources[2].metrics.observed_gross_purchase_usd = value;
    });
  }
  rejects((x) => {
    x.sources[0].metrics.first_insight_rendered = 0.5;
  });
});

test('CLI reads a bounded local file, prints JSON and emits only a fixed error on failure', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-growth-'));
  const path = join(directory, 'aggregate.json');
  const cli = (args) =>
    spawnSync(process.execPath, ['packages/shared-lib/scripts/growth-report.mjs', ...args], {
      cwd: root,
      encoding: 'utf8',
      timeout: 5000,
    });
  try {
    const input = fixture();
    input.as_of = '2026-09-02T00:00:00Z';
    for (const source of input.sources) source.watermark = input.as_of;
    writeFileSync(path, JSON.stringify(input));
    assert.equal((await run([path])).visibility, 'private_operator_only');
    const success = cli([path]);
    assert.equal(success.status, 0, success.stderr);
    assert.equal(JSON.parse(success.stdout).metrics[0].value, 10);
    writeFileSync(path, ' '.repeat(MAX_INPUT_BYTES + 1));
    await assert.rejects(run([path]));
    writeFileSync(path, '{"email":"private-value"}');
    for (const args of [[], [path, 'extra'], [path], [join(directory, 'private-value')]]) {
      const result = cli(args);
      assert.equal(result.status, 1);
      assert.equal(result.stdout, '');
      assert.equal(
        result.stderr,
        'Growth report rejected: invalid or unreadable private aggregate input.\n',
      );
    }
    writeFileSync(path, '{');
    await assert.rejects(run([path]));
    mkdirSync(join(directory, 'folder'));
    await assert.rejects(run([join(directory, 'folder')]));
    symlinkSync(path, join(directory, 'link'));
    await assert.rejects(run([join(directory, 'link')]));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
