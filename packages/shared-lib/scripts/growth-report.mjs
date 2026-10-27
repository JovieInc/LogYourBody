import { open } from 'node:fs/promises';
import { constants } from 'node:fs';
import { Buffer } from 'node:buffer';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const DAY = 86_400_000;
export const MAX_INPUT_BYTES = 65_536;
const EXCLUSIONS = ['sandbox', 'testflight', 'qa', 'synthetic', 'duplicates'];
const DEFINITIONS = {
  onboarding_started: { source: 'statsig', kind: 'count', unit: 'anonymous_events' },
  first_insight_rendered: { source: 'statsig', kind: 'count', unit: 'anonymous_events' },
  activation_v1: { source: 'core_data_neon', kind: 'cohort', days: 1 },
  d7_retention_v1: { source: 'core_data_neon', kind: 'cohort', days: 9 },
  d30_retention_v1: { source: 'core_data_neon', kind: 'cohort', days: 32 },
  supported_charge_count: { source: 'revenuecat', kind: 'count', unit: 'transactions' },
  observed_gross_purchase_usd: { source: 'revenuecat', kind: 'money', unit: 'USD' },
  supported_observed_mrr_usd: { source: 'revenuecat', kind: 'money', unit: 'USD_per_month' },
};

// Errors are deliberately fixed text: never echo an input key, value or path.
function requireValid(condition) {
  if (!condition) throw new Error('Invalid private growth evidence');
}

function object(value, keys, required = keys) {
  requireValid(value !== null && typeof value === 'object' && !Array.isArray(value));
  requireValid(Object.keys(value).every((key) => keys.includes(key)));
  requireValid(required.every((key) => Object.hasOwn(value, key)));
}

function utc(value) {
  requireValid(typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(value));
  const result = Date.parse(value);
  requireValid(
    Number.isFinite(result) && new Date(result).toISOString() === value.replace('Z', '.000Z'),
  );
  return result;
}

function count(value) {
  requireValid(Number.isSafeInteger(value) && value >= 0 && value <= 10_000_000);
}

function validateMetric(value, definition) {
  if (definition.kind === 'cohort') {
    object(value, ['numerator', 'denominator', 'missing']);
    count(value.numerator);
    count(value.denominator);
    count(value.missing);
    requireValid(value.denominator > 0 && value.numerator + value.missing <= value.denominator);
  } else if (value !== null) {
    requireValid(
      typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1_000_000_000,
    );
    if (definition.kind === 'count') count(value);
  }
}

function validate(input, now) {
  object(input, ['schema_version', 'environment', 'source_revision', 'as_of', 'window', 'sources']);
  requireValid(input.schema_version === 1 && input.environment === 'production');
  requireValid(
    typeof input.source_revision === 'string' && /^[a-f0-9]{40}$/.test(input.source_revision),
  );
  const asOf = utc(input.as_of);
  requireValid(asOf <= now.getTime());
  object(input.window, ['from', 'to']);
  const from = utc(input.window.from);
  const to = utc(input.window.to);
  requireValid(from < to && to <= asOf && to - from <= 90 * DAY);
  requireValid(Array.isArray(input.sources) && input.sources.length <= 3);
  const sources = new Set();
  const receipts = new Set();
  for (const source of input.sources) {
    object(source, [
      'source',
      'environment',
      'receipt_sha256',
      'from',
      'to',
      'watermark',
      'commissioned',
      'reconciled',
      'exclusions',
      'metrics',
    ]);
    requireValid(['statsig', 'core_data_neon', 'revenuecat'].includes(source.source));
    requireValid(source.environment === 'production' && !sources.has(source.source));
    requireValid(
      typeof source.receipt_sha256 === 'string' && /^[a-f0-9]{64}$/.test(source.receipt_sha256),
    );
    requireValid(!receipts.has(source.receipt_sha256));
    sources.add(source.source);
    receipts.add(source.receipt_sha256);
    requireValid(source.from === input.window.from && source.to === input.window.to);
    requireValid(utc(source.watermark) <= asOf);
    requireValid(
      typeof source.commissioned === 'boolean' && typeof source.reconciled === 'boolean',
    );
    requireValid(
      Array.isArray(source.exclusions) &&
        source.exclusions.length === EXCLUSIONS.length &&
        EXCLUSIONS.every((exclusion) => source.exclusions.includes(exclusion)),
    );
    const allowed = Object.keys(DEFINITIONS).filter(
      (key) => DEFINITIONS[key].source === source.source,
    );
    object(source.metrics, allowed, []);
    for (const [key, value] of Object.entries(source.metrics))
      validateMetric(value, DEFINITIONS[key]);
    for (const metric of ['d7_retention_v1', 'd30_retention_v1']) {
      if (source.metrics[metric]) {
        requireValid(
          source.metrics.activation_v1 !== undefined &&
            source.metrics[metric].denominator === source.metrics.activation_v1.numerator,
        );
      }
    }
  }
}

function iterationPlan(rows, snapshotStatus) {
  const nextActions = [];
  if (snapshotStatus === 'stale') {
    nextActions.push({
      action: 'refresh_report_snapshot',
      source: null,
      metrics: [],
      not_before: null,
    });
  }
  // Only fixed action codes and schema-validated fields leave the tool.
  // A low or missing count never automatically selects a variant or changes a gate.
  for (const [issue, action] of [
    ['unknown', 'collect_missing_aggregate'],
    ['uncommissioned', 'commission_source'],
    ['unreconciled', 'reconcile_source'],
    ['stale', 'refresh_source_coverage'],
    ['incomplete', 'complete_cohort_coverage'],
    ['immature', 'wait_for_cohort_maturity'],
  ]) {
    for (const source of ['statsig', 'core_data_neon', 'revenuecat']) {
      const affected = rows.filter((row) => row.source === source && row.issues.includes(issue));
      if (affected.length === 0) continue;
      nextActions.push({
        action,
        source,
        metrics: affected.map((row) => row.metric),
        not_before:
          issue === 'immature'
            ? affected
                .map((row) => row.observation_closes_at)
                .sort()
                .at(-1)
            : null,
      });
    }
  }
  return {
    status: nextActions.length ? 'repair_measurement' : 'review_qualified_aggregates',
    experiment_decision: 'not_evaluated',
    next_actions: nextActions,
  };
}

export function generateReport(input, now = new Date()) {
  validate(input, now);
  const asOf = utc(input.as_of);
  const rows = Object.entries(DEFINITIONS).map(([metric, definition]) => {
    const source = input.sources.find((item) => item.source === definition.source);
    const observation = source?.metrics[metric];
    const issues = [];
    if (observation === undefined || observation === null) issues.push('unknown');
    if (source) {
      const watermark = utc(source.watermark);
      if (asOf - watermark > DAY || watermark < utc(input.window.to)) issues.push('stale');
      if (!source.commissioned) issues.push('uncommissioned');
      if (!source.reconciled) issues.push('unreconciled');
      // Entire [from,to) cohort must close, including the last member's window.
      if (definition.days && watermark < utc(input.window.to) + definition.days * DAY)
        issues.push('immature');
      if (
        definition.kind === 'cohort' &&
        (observation?.missing > 0 || source.metrics.activation_v1?.missing > 0)
      )
        issues.push('incomplete');
    }
    const qualified = issues.length === 0;
    return {
      metric,
      source: definition.source,
      unit: definition.unit ?? 'eligible_principals_v1',
      status: qualified ? 'qualified' : issues.join(','),
      issues,
      receipt_sha256: source?.receipt_sha256 ?? null,
      watermark: source?.watermark ?? null,
      observation_closes_at: definition.days
        ? new Date(utc(input.window.to) + definition.days * DAY).toISOString()
        : null,
      observation: observation ?? null,
      value: qualified
        ? definition.kind === 'cohort'
          ? observation.numerator / observation.denominator
          : observation
        : null,
    };
  });
  const snapshotStatus = now.getTime() - asOf > DAY ? 'stale' : 'current_as_of';
  return {
    schema_version: 1,
    visibility: 'private_operator_only',
    environment: 'production',
    source_revision: input.source_revision,
    generated_at: now.toISOString(),
    as_of: input.as_of,
    window: input.window,
    exclusions: EXCLUSIONS,
    snapshot_status: snapshotStatus,
    evidence_scope:
      'Operator-supplied aggregates; receipt hashes and attestations are not independently verified.',
    provider_commissioning: 'not_independently_verified',
    metrics: rows,
    iteration: iterationPlan(rows, snapshotStatus),
    qualified_coaching_activation: { status: 'unknown', value: null },
    first_insight_conversion: { status: 'unknown', value: null },
    trial_to_paid_conversion: { status: 'unknown', value: null },
    net_revenue_usd: { status: 'unreconciled', value: null },
    refunds: { status: 'unreconciled', value: null },
    customer_outcomes: { status: 'unknown', value: null },
  };
}

export function parseInput(text) {
  const input = JSON.parse(text);
  // JSON.parse silently accepts repeated keys (including escaped equivalents).
  // Reject them before a sandbox label or sensitive field can be overwritten.
  const containers = [];
  let previous;
  for (const [token] of text.matchAll(/"(?:\\[\s\S]|[^"\\])*"|[{}[\]:,]/g)) {
    if (token === '{' || token === '[') containers.push(token === '{' ? new Set() : null);
    else if (token === '}' || token === ']') containers.pop();
    else if (token === ':') {
      const key = JSON.parse(previous);
      const keys = containers.at(-1);
      requireValid(!keys.has(key));
      keys.add(key);
    }
    previous = token;
  }
  return input;
}

export async function run(argv) {
  // One local, regular file. No URLs, stdin, provider clients, output files or scheduler.
  requireValid(argv.length === 1);
  const handle = await open(
    argv[0],
    constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW,
  );
  let buffer;
  try {
    const info = await handle.stat();
    requireValid(info.isFile() && info.size <= MAX_INPUT_BYTES);
    buffer = Buffer.alloc(MAX_INPUT_BYTES + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await handle.read(buffer, length, buffer.length - length, length);
      if (bytesRead === 0) break;
      length += bytesRead;
    }
    requireValid(length <= MAX_INPUT_BYTES);
    buffer = buffer.subarray(0, length);
  } finally {
    await handle.close();
  }
  const input = parseInput(buffer.toString('utf8'));
  return generateReport(input);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.stdout.write(`${JSON.stringify(await run(process.argv.slice(2)), null, 2)}\n`);
  } catch {
    process.stderr.write(
      'Growth report rejected: invalid or unreadable private aggregate input.\n',
    );
    process.exitCode = 1;
  }
}
