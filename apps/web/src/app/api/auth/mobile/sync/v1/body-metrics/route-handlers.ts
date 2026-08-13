import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import {
  NATIVE_BODY_METRICS_SYNC_VERSION,
  type NativeBodyMetricsSyncPort,
} from '@/lib/ports/native-body-metrics-sync';

const DATA_SOURCES = [
  'manual',
  'healthkit',
  'smart_scale',
  'bodyspec_dexa',
  'caliper',
  'photo',
] as const;

const isoDateTime = z.string().refine((value) => Number.isFinite(Date.parse(value)), {
  message: 'invalid_datetime',
});

const NativeBodyMetricPushSchema = z
  .object({
    id: z.string().uuid(),
    user_id: z.string().optional(),
    date: isoDateTime,
    local_date: z.string().date(),
    weight: z.number().finite().nullable(),
    weight_unit: z.enum(['kg', 'lbs']),
    waist_circumference: z.number().finite().nullable(),
    hip_circumference: z.number().finite().nullable(),
    waist_unit: z.enum(['cm', 'in']),
    body_fat_percentage: z.number().finite().nullable(),
    body_fat_method: z.string().max(40).nullable(),
    muscle_mass: z.number().finite().nullable(),
    bone_mass: z.number().finite().nullable(),
    photo_url: z.string().max(2000).nullable(),
    notes: z.string().max(2000).nullable(),
    data_source: z.enum(DATA_SOURCES),
    source_metadata: z.record(z.string(), z.unknown()),
    created_at: isoDateTime,
    updated_at: isoDateTime,
  })
  .strict();

const PushBodySchema = z
  .object({
    records: z.array(NativeBodyMetricPushSchema).min(1).max(100),
  })
  .strict();

const DeleteBodySchema = z
  .object({
    ids: z.array(z.string().uuid()).min(1).max(100),
  })
  .strict();

const PullQuerySchema = z.object({
  since: isoDateTime.optional(),
  after_id: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
});

type NativeSyncRouteDependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  sync: NativeBodyMetricsSyncPort;
};

function json(payload: unknown, status = 200) {
  return NextResponse.json(payload, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  });
}

function mapPushRecord(record: z.infer<typeof NativeBodyMetricPushSchema>) {
  return {
    id: record.id,
    date: new Date(record.date).toISOString(),
    local_date: record.local_date,
    weight: record.weight,
    weight_unit: record.weight_unit,
    waist_circumference: record.waist_circumference,
    hip_circumference: record.hip_circumference,
    waist_unit: record.waist_unit,
    body_fat_percentage: record.body_fat_percentage,
    body_fat_method: record.body_fat_method,
    muscle_mass: record.muscle_mass,
    bone_mass: record.bone_mass,
    photo_url: record.photo_url,
    notes: record.notes,
    data_source: record.data_source,
    source_metadata: record.source_metadata,
    created_at: new Date(record.created_at).toISOString(),
    updated_at: new Date(record.updated_at).toISOString(),
  };
}

export function createNativeBodyMetricsSyncHandlers(deps: NativeSyncRouteDependencies) {
  return {
    async GET(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);

      const parsed = PullQuerySchema.safeParse({
        since: request.nextUrl.searchParams.get('since') ?? undefined,
        after_id: request.nextUrl.searchParams.get('after_id') ?? undefined,
        limit: request.nextUrl.searchParams.get('limit') ?? undefined,
      });
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_pull' }, 400);
      }

      const result = await deps.sync.pull(identity.sub, {
        since: parsed.data.since ?? '1970-01-01T00:00:00.000Z',
        after_id: parsed.data.after_id ?? null,
        limit: parsed.data.limit,
      });
      return json({
        version: NATIVE_BODY_METRICS_SYNC_VERSION,
        ...result,
        records: result.records.map((record) => ({ ...record, user_id: identity.sub })),
      });
    },

    async POST(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);

      const parsed = PushBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_records' }, 400);
      }

      const result = await deps.sync.push(identity.sub, parsed.data.records.map(mapPushRecord));
      return json(
        {
          version: NATIVE_BODY_METRICS_SYNC_VERSION,
          ...result,
          records: result.records.map((record) => ({ ...record, user_id: identity.sub })),
        },
        200,
      );
    },

    async DELETE(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);

      const parsed = DeleteBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_delete' }, 400);
      }

      const result = await deps.sync.remove(identity.sub, parsed.data.ids);
      return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, ...result });
    },
  };
}
