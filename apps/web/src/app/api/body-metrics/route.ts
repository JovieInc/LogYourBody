import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

const BodyMetricSchema = z.object({
  date: z.string().date(),
  weight: z.number().positive().max(1000).nullable().optional(),
  weightUnit: z.enum(['kg', 'lbs']).default('kg'),
  bodyFatPercentage: z.number().min(0).max(70).nullable().optional(),
  bodyFatMethod: z.string().max(20).nullable().optional(),
  muscleMass: z.number().positive().max(1000).nullable().optional(),
  waist: z.number().positive().max(500).nullable().optional(),
  neck: z.number().positive().max(500).nullable().optional(),
  hip: z.number().positive().max(500).nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
  photoUrl: z.string().url().nullable().optional(),
  dataSource: z
    .enum(['manual', 'healthkit', 'smart_scale', 'bodyspec_dexa', 'caliper', 'photo'])
    .default('manual'),
  sourceMetadata: z.record(z.string(), z.unknown()).default({}),
});

export async function POST(request: NextRequest) {
  const { userId } = await getServerAuthSession();
  if (!userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const parsed = BodyMetricSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: 'Invalid body metric' }, { status: 400 });

  const input = parsed.data;
  const metric = await neonBodyMetrics.upsert(userId, {
    date: input.date,
    weight: input.weight ?? null,
    weight_unit: input.weightUnit,
    body_fat_percentage: input.bodyFatPercentage ?? null,
    body_fat_method: input.bodyFatMethod ?? null,
    muscle_mass: input.muscleMass ?? null,
    waist: input.waist ?? null,
    neck: input.neck ?? null,
    hip: input.hip ?? null,
    notes: input.notes ?? null,
    photo_url: input.photoUrl ?? null,
    data_source: input.dataSource,
    source_metadata: input.sourceMetadata,
  });

  return NextResponse.json({ metric }, { status: 201 });
}

export async function GET() {
  const { userId } = await getServerAuthSession();
  if (!userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const metrics = await neonBodyMetrics.list(userId, 100);
  return NextResponse.json(
    {
      metrics: metrics.map(({ user_subject, ...metric }) => ({ ...metric, user_id: user_subject })),
    },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
