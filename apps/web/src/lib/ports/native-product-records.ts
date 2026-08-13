export const NATIVE_PRODUCT_RECORD_COLLECTIONS = [
  'daily_metrics',
  'glp1_medications',
  'glp1_dose_logs',
  'dexa_results',
  'progress_photos',
] as const;

export type NativeProductRecordCollection = (typeof NATIVE_PRODUCT_RECORD_COLLECTIONS)[number];

export type NativeProductRecord = Record<string, unknown> & {
  id: string;
  deleted_at: string | null;
  server_updated_at: string;
};

export type NativeProductRecordsPullCursor = {
  since: string;
  after_id: string | null;
};

export interface NativeProductRecordsPort {
  push(
    subject: string,
    collection: NativeProductRecordCollection,
    records: Array<Record<string, unknown>>,
  ): Promise<{ records: NativeProductRecord[]; rejected_ids: string[] }>;
  pull(
    subject: string,
    collection: NativeProductRecordCollection,
    input: NativeProductRecordsPullCursor & { limit?: number },
  ): Promise<{
    records: NativeProductRecord[];
    deleted_ids: string[];
    next_cursor: NativeProductRecordsPullCursor | null;
  }>;
  remove(
    subject: string,
    collection: NativeProductRecordCollection,
    ids: string[],
  ): Promise<{ deleted_ids: string[] }>;
  endActiveGlp1Medications(subject: string, endedAt: string): Promise<{ updated: number }>;
  listAll(subject: string): Promise<Record<NativeProductRecordCollection, NativeProductRecord[]>>;
  deleteAllForSubject(subject: string): Promise<void>;
}

export function isNativeProductRecordCollection(
  value: string,
): value is NativeProductRecordCollection {
  return (NATIVE_PRODUCT_RECORD_COLLECTIONS as readonly string[]).includes(value);
}

export function collectionFromPath(value: string): NativeProductRecordCollection | null {
  const normalized = value.replace(/-/g, '_');
  return isNativeProductRecordCollection(normalized) ? normalized : null;
}
