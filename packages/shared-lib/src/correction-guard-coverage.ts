// Correction-guard coverage (LYB-309). Pure count over classified ledger
// corrections. Codebase and lint/typecheck/CI (`static`) form the denominator.
// Prose and human review do not. A codebase correction is covered by
// construction. A lint/typecheck/CI correction is covered only when a
// mechanized check exists. Repeated receipts collapse to one rule per
// fingerprint, matching the ledger. LYB-188 and LYB-189 are not inputs.

const CODEBASE = new Set(['codebase']);
const LINT = new Set(['static', 'lint', 'typecheck', 'ci', 'lint/typecheck/ci']);
const OUTSIDE = new Set(['prose', 'human', 'human-review', 'unclassified']);
const MIN_ANCHOR_LENGTH = 16;

export interface CorrectionGuardRef {
  path?: string;
  anchor?: string;
}

/** One classified ledger correction or an already-collapsed rule. */
export interface ClassifiedLedgerCorrection {
  fingerprint?: string;
  level?: string;
  guard?: CorrectionGuardRef | null;
  /** File-checked result. When set, it decides whether a lint check exists. */
  mechanized?: boolean;
  classification?: unknown;
  proseOnlyReason?: string | null;
  correction?: string;
  source?: string;
  mechanization?: string;
  ruleId?: string;
}

export interface CorrectionGuardCoverage {
  covered: number;
  total: number;
  /** `covered / total`. Null when the denominator is empty — never 100%. */
  ratio: number | null;
}

type Bucket = 'codebase' | 'lint' | 'outside';

function normalizeLevel(level: unknown): string {
  return typeof level === 'string' ? level.trim().toLowerCase().replace(/\s+/g, '') : '';
}

function normalizeFingerprint(fingerprint: unknown): string | null {
  if (typeof fingerprint !== 'string') return null;
  const normalized = fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
  return normalized.length > 0 ? normalized : null;
}

function bucketFor(level: string): Bucket {
  if (CODEBASE.has(level)) return 'codebase';
  if (LINT.has(level)) return 'lint';
  if (OUTSIDE.has(level)) return 'outside';
  throw new Error(`unknown correction classification: ${level || '(missing)'}`);
}

/** A lint/typecheck/CI correction is guarded only when its check exists. */
function mechanizedCheckExists(correction: ClassifiedLedgerCorrection): boolean {
  if (typeof correction.mechanized === 'boolean') return correction.mechanized;
  const guard = correction.guard;
  if (!guard) return false;
  const path = typeof guard.path === 'string' ? guard.path.trim() : '';
  const anchor = typeof guard.anchor === 'string' ? guard.anchor.trim() : '';
  return path.length > 0 && anchor.length >= MIN_ANCHOR_LENGTH;
}

function isCovered(bucket: Bucket, correction: ClassifiedLedgerCorrection): boolean {
  if (bucket === 'codebase') return true;
  if (bucket === 'lint') return mechanizedCheckExists(correction);
  return false;
}

/**
 * Covered and total correction-guard counts for one ledger snapshot.
 * Each distinct fingerprint counts once. Corrections with no fingerprint
 * count individually, so fixtures do not have to invent identities.
 */
export function correctionGuardCoverage(
  corrections: readonly ClassifiedLedgerCorrection[],
): CorrectionGuardCoverage {
  if (!Array.isArray(corrections)) {
    throw new Error('correction guard coverage expects classified ledger corrections');
  }

  const rules = new Map<string, { bucket: Bucket; covered: boolean }>();
  let anonymous = 0;

  for (const correction of corrections) {
    const level = normalizeLevel(correction?.level);
    const bucket = bucketFor(level);
    const fingerprint = normalizeFingerprint(correction?.fingerprint);
    const key = fingerprint ?? `anonymous:${anonymous}`;
    if (fingerprint === null) anonymous += 1;

    if (bucket === 'outside' && fingerprint === null) continue;

    const covered = isCovered(bucket, correction);
    const previous = rules.get(key);
    if (!previous) {
      rules.set(key, { bucket, covered });
      continue;
    }
    if (previous.bucket !== bucket || previous.covered !== covered) {
      throw new Error(`conflicting coverage annotations: ${fingerprint ?? key}`);
    }
  }

  let covered = 0;
  let total = 0;
  for (const rule of rules.values()) {
    if (rule.bucket === 'outside') continue;
    total += 1;
    if (rule.covered) covered += 1;
  }

  return { covered, total, ratio: total === 0 ? null : covered / total };
}
