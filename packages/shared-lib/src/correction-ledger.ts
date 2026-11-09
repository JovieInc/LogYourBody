// Record a classified correction into the LYB ledger (LYB-308).
// Rule summaries use the classifier's rule id; receipt intake also matches
// normalized text and level. Neither path emits checks or replaces fingerprint counts.

export type ClassifiedCorrection = {
  ruleId: string;
};

export type CorrectionRecord<T extends ClassifiedCorrection = ClassifiedCorrection> = T & {
  recurrence: number;
};

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
