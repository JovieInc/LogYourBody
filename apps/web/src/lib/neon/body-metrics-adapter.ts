import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type { BodyMetricsPort, ProductBodyMetric } from '@/lib/ports/body-metrics';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

const columns = `
  id, user_subject, date, weight, weight_unit, body_fat_percentage,
  body_fat_method, muscle_mass, waist, neck, hip, notes, photo_url,
  data_source, source_metadata, created_at, updated_at
`;

export const neonBodyMetrics: BodyMetricsPort = {
  async list(subject, limit = 30) {
    return (await getDatabase().query(
      `select ${columns} from public.body_metrics
       where user_subject = $1 order by date desc, created_at desc limit $2`,
      [subject, Math.min(Math.max(limit, 1), 100)],
    )) as ProductBodyMetric[];
  },

  async upsert(subject, metric) {
    const rows = (await getDatabase().query(
      `insert into public.body_metrics (
         user_subject, date, weight, weight_unit, body_fat_percentage,
         body_fat_method, muscle_mass, waist, neck, hip, notes, photo_url,
         data_source, source_metadata
       ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       on conflict (user_subject, date) do update set
         weight = excluded.weight,
         weight_unit = excluded.weight_unit,
         body_fat_percentage = excluded.body_fat_percentage,
         body_fat_method = excluded.body_fat_method,
         muscle_mass = excluded.muscle_mass,
         waist = excluded.waist,
         neck = excluded.neck,
         hip = excluded.hip,
         notes = excluded.notes,
         photo_url = excluded.photo_url,
         data_source = excluded.data_source,
         source_metadata = excluded.source_metadata,
         updated_at = now()
       returning ${columns}`,
      [
        subject,
        metric.date,
        metric.weight,
        metric.weight_unit,
        metric.body_fat_percentage,
        metric.body_fat_method,
        metric.muscle_mass,
        metric.waist,
        metric.neck,
        metric.hip,
        metric.notes,
        metric.photo_url,
        metric.data_source,
        JSON.stringify(metric.source_metadata),
      ],
    )) as ProductBodyMetric[];
    if (!rows[0]) throw new Error('Body metric was not persisted');
    return rows[0];
  },
};
