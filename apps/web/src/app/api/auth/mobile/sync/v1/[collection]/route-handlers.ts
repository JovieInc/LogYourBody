import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { NATIVE_BODY_METRICS_SYNC_VERSION } from '@/lib/ports/native-body-metrics-sync';
import {
  collectionFromPath,
  type NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';

const isoDateTime = z.string().refine((value) => Number.isFinite(Date.parse(value)), {
  message: 'invalid_datetime',
});

const NativeRecordSchema = z
  .object({
    id: z.string().uuid(),
    user_id: z.string().optional(),
  })
  .passthrough();

const PushBodySchema = z.union([
  z.object({ records: z.array(NativeRecordSchema).min(1).max(100) }).strict(),
  z.array(NativeRecordSchema).min(1).max(100),
]);

const DeleteBodySchema = z
  .object({
    ids: z.array(z.string().uuid()).min(1).max(100),
  })
  .strict();

const EndActiveBodySchema = z
  .object({
    ended_at: isoDateTime,
  })
  .strict();

const PullQuerySchema = z.object({
  since: isoDateTime.optional(),
  after_id: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
});

type RouteDependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  records: NativeProductRecordsPort;
};

function json(payload: unknown, status = 200) {
  return NextResponse.json(payload, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  });
}

function collectionParam(request: NextRequest) {
  const value = request.nextUrl.pathname.split('/').at(-1) || '';
  return collectionFromPath(value);
}

function pushRecords(body: z.infer<typeof PushBodySchema>) {
  return Array.isArray(body) ? body : body.records;
}

export function createNativeProductRecordHandlers(deps: RouteDependencies) {
  return {
    async GET(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);
      const collection = collectionParam(request);
      if (!collection)
        return json(
          { version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unknown_collection' },
          404,
        );

      const parsed = PullQuerySchema.safeParse({
        since: request.nextUrl.searchParams.get('since') ?? undefined,
        after_id: request.nextUrl.searchParams.get('after_id') ?? undefined,
        limit: request.nextUrl.searchParams.get('limit') ?? undefined,
      });
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_pull' }, 400);
      }

      const result = await deps.records.pull(identity.sub, collection, {
        since: parsed.data.since ?? '1970-01-01T00:00:00.000Z',
        after_id: parsed.data.after_id ?? null,
        limit: parsed.data.limit,
      });
      return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, ...result });
    },

    async POST(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);
      const collection = collectionParam(request);
      if (!collection)
        return json(
          { version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unknown_collection' },
          404,
        );

      const payload = await request.json().catch(() => null);
      if (
        collection === 'glp1_medications' &&
        payload &&
        typeof payload === 'object' &&
        !Array.isArray(payload) &&
        'ended_at' in payload &&
        !('records' in payload)
      ) {
        const parsed = EndActiveBodySchema.safeParse(payload);
        if (!parsed.success) {
          return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_records' }, 400);
        }
        const result = await deps.records.endActiveGlp1Medications(
          identity.sub,
          new Date(parsed.data.ended_at).toISOString(),
        );
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, ...result });
      }

      const parsed = PushBodySchema.safeParse(payload);
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_records' }, 400);
      }

      const result = await deps.records.push(identity.sub, collection, pushRecords(parsed.data));
      return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, ...result });
    },

    async DELETE(request: NextRequest) {
      const identity = await deps.authenticate(request);
      if (!identity)
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unauthorized' }, 401);
      const collection = collectionParam(request);
      if (!collection)
        return json(
          { version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'unknown_collection' },
          404,
        );

      const parsed = DeleteBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) {
        return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, error: 'invalid_delete' }, 400);
      }

      const result = await deps.records.remove(identity.sub, collection, parsed.data.ids);
      return json({ version: NATIVE_BODY_METRICS_SYNC_VERSION, ...result });
    },
  };
}
