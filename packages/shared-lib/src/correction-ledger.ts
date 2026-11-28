// Record a classified correction into the LYB ledger (LYB-308).
// Rule summaries use the classifier's rule id; receipt intake also matches
// normalized text and level. Neither path emits checks or replaces fingerprint counts.

import {
  classifyCorrection,
  type CorrectionClassification,
  type CorrectionLevel,
} from '../scripts/correction-classification.mjs';

export type {
  CorrectionClassification,
  CorrectionLevel,
} from '../scripts/correction-classification.mjs';

export type ClassifiedCorrection = {
  ruleId: string;
};

export type CorrectionRecord<T extends ClassifiedCorrection = ClassifiedCorrection> = T & {
  recurrence: number;
};

/** Save the first feasible pyramid level, replacing any stale saved label. */
export function classifyCorrectionRecords<
  T extends ClassifiedCorrection & { classification: CorrectionClassification },
>(
  ledger: readonly CorrectionRecord<T>[],
): (Omit<CorrectionRecord<T>, 'level'> & { level: CorrectionLevel })[] {
  return ledger.map((record) => ({
    ...record,
    level: classifyCorrection(
      { fingerprint: record.ruleId, classification: record.classification },
      true,
    ).level,
  }));
}

export type CorrectionPyramidCoverage = {
  levels: Record<CorrectionLevel, number>;
  total: number;
  mechanized: number;
  /** `(codebase + static) / total` on a 0–1 scale; zero for an empty ledger. */
  mechanizedShare: number;
};

/** Count each classified ledger row once, without weighting recurrence or checking guards. */
export function correctionPyramidCoverage(
  ledger: readonly { level: CorrectionLevel }[],
): CorrectionPyramidCoverage {
  const levels = { codebase: 0, static: 0, prose: 0, human: 0 };
  for (const { level } of ledger) levels[level] += 1;
  const total = ledger.length;
  const mechanized = levels.codebase + levels.static;
  return { levels, total, mechanized, mechanizedShare: total === 0 ? 0 : mechanized / total };
}

function requiredRuleId(ruleId: string): string {
  if (typeof ruleId !== 'string' || ruleId.trim() === '') {
    throw new Error('correction rule id is required');
  }
  return ruleId;
}

function recurrenceCount(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error('invalid correction recurrence');
  }
  return value;
}

export function recordCorrection<T extends ClassifiedCorrection>(
  ledger: readonly CorrectionRecord<T>[],
  correction: T,
): CorrectionRecord<T>[] {
  const ruleId = requiredRuleId(correction.ruleId);
  const index = ledger.findIndex((record) => record.ruleId === ruleId);
  if (index === -1) {
    return [...ledger, { ...correction, ruleId, recurrence: 0 }];
  }
  return ledger.map((record, recordIndex) =>
    recordIndex === index
      ? { ...record, recurrence: recurrenceCount(record.recurrence) + 1 }
      : record,
  );
}

export type ClassifiedCorrectionReceipt = ClassifiedCorrection & {
  correction: string;
  level: 'codebase' | 'static' | 'prose' | 'human';
};

export type CorrectionReceipt<T extends ClassifiedCorrectionReceipt = ClassifiedCorrectionReceipt> =
  CorrectionRecord<T> & { isRecurrence: boolean };

export type MechanizeRequest<T extends ClassifiedCorrectionReceipt = ClassifiedCorrectionReceipt> =
  {
    type: 'mechanize';
    correction: CorrectionReceipt<T>;
  };

function normalizedCorrection(text: string): string {
  const normalized = text.normalize('NFKC').trim().toLowerCase().replace(/\s+/gu, ' ');
  if (normalized === '') throw new Error('correction text is required');
  return normalized;
}

/** Append a classified receipt and send only this new recurrence to the internal queue. */
export function recordCorrectionReceipt<
  T extends ClassifiedCorrectionReceipt,
  Previous extends ClassifiedCorrectionReceipt = never,
>(
  ledger: readonly Previous[],
  correction: T,
  enqueueMechanize: (request: MechanizeRequest<T>) => void,
): (Previous | CorrectionReceipt<T>)[] {
  const ruleId = requiredRuleId(correction.ruleId);
  const text = normalizedCorrection(correction.correction);
  const recurrence = ledger.filter(
    (receipt) =>
      receipt.level === correction.level && normalizedCorrection(receipt.correction) === text,
  ).length;
  const receipt = { ...correction, ruleId, recurrence, isRecurrence: recurrence > 0 };
  if (receipt.isRecurrence) enqueueMechanize({ type: 'mechanize', correction: receipt });
  return [...ledger, receipt];
}
