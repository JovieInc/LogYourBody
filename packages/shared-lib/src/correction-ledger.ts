// Record a classified correction into the LYB ledger (LYB-308).
// Identity is the rule id the classifier already assigned. This update does
// not emit checks and does not replace fingerprint repeat counts.

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
