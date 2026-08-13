export const NATIVE_BODY_METRICS_SYNC_VERSION = 1 as const;

export type NativeBodyMetricSyncRecord = {
  id: string;
  date: string;
  local_date: string;
  weight: number | null;
  weight_unit: 'kg' | 'lbs';
  waist_circumference: number | null;
  hip_circumference: number | null;
  waist_unit: 'cm' | 'in';
  body_fat_percentage: number | null;
  body_fat_method: string | null;
  muscle_mass: number | null;
  bone_mass: number | null;
  photo_url: string | null;
  notes: string | null;
  data_source: string;
  source_metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  server_updated_at: string;
};

export type NativeBodyMetricPushInput = Omit<
  NativeBodyMetricSyncRecord,
  'deleted_at' | 'server_updated_at'
>;

export type NativeBodyMetricsPullCursor = {
  since: string;
  after_id: string | null;
};

export type NativeBodyMetricsPullResult = {
  records: NativeBodyMetricSyncRecord[];
  deleted_ids: string[];
  next_cursor: NativeBodyMetricsPullCursor | null;
};

export type NativeBodyMetricsPushResult = {
  records: NativeBodyMetricSyncRecord[];
  rejected_ids: string[];
};

export interface NativeBodyMetricsSyncPort {
  push(subject: string, records: NativeBodyMetricPushInput[]): Promise<NativeBodyMetricsPushResult>;
  pull(
    subject: string,
    input: NativeBodyMetricsPullCursor & { limit?: number },
  ): Promise<NativeBodyMetricsPullResult>;
  remove(subject: string, ids: string[]): Promise<{ deleted_ids: string[] }>;
}
