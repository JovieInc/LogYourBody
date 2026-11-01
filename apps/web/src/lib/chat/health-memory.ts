export const HEALTH_MEMORY_PRODUCT_ID = 'lyb';

export const healthMemoryProvenance = [
  'measured',
  'engine-derived',
  'user-declared',
  'coach-inferred',
] as const;

export type HealthMemoryProvenance = (typeof healthMemoryProvenance)[number];

export type HealthMemoryRecord = {
  userId: string;
  productId: typeof HEALTH_MEMORY_PRODUCT_ID;
  text: string;
  provenance: HealthMemoryProvenance;
  recordedAt: string;
};

export type HealthMemoryFailure = 'safetyUnavailable' | 'isolated';

export type HealthMemoryResult =
  { ok: true; records: HealthMemoryRecord[] } | { ok: false; reason: HealthMemoryFailure };

export function rememberHealthMemory(
  records: HealthMemoryRecord[],
  claim: HealthMemoryRecord,
): HealthMemoryRecord[] | null {
  const text = claim.text.trim();
  if (!claim.userId || claim.productId !== HEALTH_MEMORY_PRODUCT_ID || !text) return null;
  if (!healthMemoryProvenance.includes(claim.provenance)) return null;
  return [...records, { ...claim, text }];
}

/** Unavailable safety checks return no records. Another user or product is isolated. */
export function retrieveHealthMemory(input: {
  records: HealthMemoryRecord[];
  userId: string;
  productId: string;
  safetyAvailable: boolean;
}): HealthMemoryResult {
  if (!input.safetyAvailable) return { ok: false, reason: 'safetyUnavailable' };
  if (!input.userId || input.productId !== HEALTH_MEMORY_PRODUCT_ID) {
    return { ok: false, reason: 'isolated' };
  }
  return {
    ok: true,
    records: input.records.filter(
      (record) =>
        record.userId === input.userId &&
        record.productId === HEALTH_MEMORY_PRODUCT_ID &&
        record.text.trim().length > 0,
    ),
  };
}
