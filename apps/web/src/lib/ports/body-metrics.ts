export type ProductBodyMetric = {
  id: string;
  user_subject: string;
  date: string;
  weight: number | null;
  weight_unit: 'kg' | 'lbs';
  body_fat_percentage: number | null;
  body_fat_method: string | null;
  muscle_mass: number | null;
  waist: number | null;
  neck: number | null;
  hip: number | null;
  notes: string | null;
  photo_url: string | null;
  data_source: string;
  source_metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type CreateBodyMetric = Omit<ProductBodyMetric, 'id' | 'created_at' | 'updated_at'>;

export interface BodyMetricsPort {
  list(subject: string, limit?: number): Promise<ProductBodyMetric[]>;
  upsert(
    subject: string,
    metric: Omit<CreateBodyMetric, 'user_subject'>,
  ): Promise<ProductBodyMetric>;
}
