export const HEALTH_MEMORY_PRODUCT_ID = 'lyb';

/** Both fields partition health memory. Dropping either field allows a cross read. */
export const healthMemoryIsolationKey = ['userId', 'productId'] as const;

/** Result code when the safety check cannot run. The result carries no memory payload. */
export const healthMemoryFailClosed = 'safetyUnavailable' as const;

export const healthMemoryProvenance = [
  'measured',
  'engine-derived',
  'user-declared',
  'coach-inferred',
] as const;

export type HealthMemoryProvenance = (typeof healthMemoryProvenance)[number];
export type HealthMemoryIsolationField = (typeof healthMemoryIsolationKey)[number];

export type HealthMemoryRecord = {
  userId: string;
  productId: string;
  text: string;
  provenance: HealthMemoryProvenance;
  recordedAt: string;
};

export type HealthMemoryFailure = typeof healthMemoryFailClosed | 'isolated';

export type HealthMemoryResult =
  { ok: true; records: HealthMemoryRecord[] } | { ok: false; reason: HealthMemoryFailure };

function isolationFields(input: {
  userId: string;
  productId: string;
}): Record<HealthMemoryIsolationField, string> {
  return { userId: input.userId, productId: input.productId };
}

function completeIsolationKey(input: { userId: string; productId: string }): boolean {
  const fields = isolationFields(input);
  return healthMemoryIsolationKey.every((field) => fields[field].length > 0);
}

function sameIsolationKey(
  record: HealthMemoryRecord,
  query: { userId: string; productId: string },
): boolean {
  const stored = isolationFields(record);
  const requested = isolationFields(query);
  return healthMemoryIsolationKey.every((field) => stored[field] === requested[field]);
}

/**
 * Refuses the write when the safety check cannot run, or when the claim is missing
 * either isolation-key field. A refused write leaves the previous records untouched.
 */
export function rememberHealthMemory(
  records: HealthMemoryRecord[],
  claim: HealthMemoryRecord,
  safetyAvailable: boolean,
): HealthMemoryRecord[] | null {
  if (!safetyAvailable) return null;
  const text = claim.text.trim();
  if (!completeIsolationKey(claim) || !text) return null;
  if (!healthMemoryProvenance.includes(claim.provenance)) return null;
  return [...records, { ...claim, text }];
}

/** Unavailable safety checks deny the read and return no records. Another user or product is empty. */
export function retrieveHealthMemory(input: {
  records: HealthMemoryRecord[];
  userId: string;
  productId: string;
  safetyAvailable: boolean;
}): HealthMemoryResult {
  if (!input.safetyAvailable) return { ok: false, reason: healthMemoryFailClosed };
  if (!completeIsolationKey(input)) return { ok: false, reason: 'isolated' };
  return {
    ok: true,
    records: input.records.filter(
      (record) => sameIsolationKey(record, input) && record.text.trim().length > 0,
    ),
  };
}
