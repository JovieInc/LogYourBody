import { POUNDS_TO_KILOGRAMS } from '@/lib/metrics/weight-lifecycle';
import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { NativeProductRecord } from '@/lib/ports/native-product-records';
import { isVaultAssetUrl } from './urls';
import type {
  ShareField,
  VaultDexa,
  VaultPhoto,
  VaultSnapshot,
  VaultSeries,
  VaultSummary,
  VaultWeighIn,
} from './types';

const POUNDS = Number(POUNDS_TO_KILOGRAMS);

function active(rows: NativeProductRecord[]): NativeProductRecord[] {
  return rows.filter((row) => row.deleted_at == null);
}

function num(row: Record<string, unknown>, key: string): number | null {
  const value = row[key];
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value)))
    return Number(value);
  return null;
}

function text(row: Record<string, unknown>, key: string): string | null {
  const value = row[key];
  return typeof value === 'string' && value.trim() ? value : null;
}

function day(row: Record<string, unknown>): string {
  const value =
    text(row, 'acquire_time') ??
    text(row, 'measured_on') ??
    text(row, 'date') ??
    text(row, 'created_at');
  return value ? value.slice(0, 10) : '';
}

function isDexaMetric(metric: ProductBodyMetric): boolean {
  return (
    metric.body_fat_method === 'dexa' ||
    metric.data_source === 'bodyspec_dexa' ||
    metric.data_source === 'dexa_pdf'
  );
}

function weightKg(metric: ProductBodyMetric): number | null {
  if (metric.weight == null || !Number.isFinite(Number(metric.weight))) return null;
  const value = Number(metric.weight);
  if (metric.weight_unit === 'kg') return value;
  if (metric.weight_unit === 'lbs') return value * POUNDS;
  return null;
}

export function snapshotFromSources(input: {
  dexaRecords: NativeProductRecord[];
  photoRecords: NativeProductRecord[];
  bodyMetrics: ProductBodyMetric[];
  allowedOrigins: readonly string[];
}): VaultSnapshot {
  const dexa: VaultDexa[] = [];
  const photos: VaultPhoto[] = [];
  const weighIns: VaultWeighIn[] = [];
  const seen = new Set<string>();

  const pushDexa = (row: Record<string, unknown>, id: string) => {
    if (seen.has(`dexa:${id}`)) return;
    const bodyFatPercent = num(row, 'body_fat_percentage') ?? num(row, 'bodyFatPercent');
    if (bodyFatPercent == null) return;
    seen.add(`dexa:${id}`);
    dexa.push({
      id,
      measuredOn: day(row),
      bodyFatPercent,
      leanMassKg: num(row, 'muscle_mass') ?? num(row, 'leanMassKg'),
    });
  };

  const pushPhoto = (id: string, imageUrl: string | null) => {
    if (!id || seen.has(`photo:${id}`)) return;
    seen.add(`photo:${id}`);
    const allowed = imageUrl && isVaultAssetUrl(imageUrl, input.allowedOrigins) ? imageUrl : null;
    photos.push({ id, imageUrl: allowed });
  };

  for (const row of active(input.dexaRecords)) pushDexa(row, row.id);
  for (const metric of input.bodyMetrics) {
    if (isDexaMetric(metric)) {
      pushDexa(
        {
          body_fat_percentage: metric.body_fat_percentage,
          muscle_mass: metric.muscle_mass,
          date: metric.date,
        },
        metric.id,
      );
    }
    const kg = weightKg(metric);
    if (kg != null && !seen.has(`weight:${metric.id}`)) {
      seen.add(`weight:${metric.id}`);
      weighIns.push({ id: metric.id, measuredOn: metric.date.slice(0, 10), weightKg: kg });
    }
    if (metric.photo_url) pushPhoto(metric.id, metric.photo_url);
  }
  for (const row of active(input.photoRecords)) {
    const imageUrl = text(row, 'photo_url') ?? text(row, 'image_url') ?? text(row, 'url');
    pushPhoto(row.id, imageUrl);
  }

  const byDate = (a: { measuredOn: string }, b: { measuredOn: string }) =>
    a.measuredOn.localeCompare(b.measuredOn);
  dexa.sort(byDate);
  weighIns.sort(byDate);
  return { dexa, photos, weighIns };
}

function series(values: number[]): VaultSeries | undefined {
  if (!values.length) return undefined;
  const first = values[0]!;
  const last = values[values.length - 1]!;
  return { first, last, delta: last - first, samples: values.length };
}

export function summarizeVault(
  snapshot: VaultSnapshot,
  fields: readonly ShareField[],
): VaultSummary {
  const summary: VaultSummary = {};
  if (fields.includes('body_fat')) {
    const bodyFat = series(snapshot.dexa.map((row) => row.bodyFatPercent));
    if (bodyFat) summary.body_fat = bodyFat;
  }
  if (fields.includes('lean_mass')) {
    const lean = series(
      snapshot.dexa.flatMap((row) => (row.leanMassKg == null ? [] : [row.leanMassKg])),
    );
    if (lean) summary.lean_mass = lean;
  }
  if (fields.includes('weight')) {
    const weight = series(snapshot.weighIns.map((row) => row.weightKg));
    if (weight) summary.weight = weight;
  }
  return summary;
}

export function describeVaultSummary(summary: VaultSummary): string {
  const lines: string[] = [];
  if (summary.body_fat) {
    lines.push(
      `Body fat ${summary.body_fat.first}% to ${summary.body_fat.last}% (change ${summary.body_fat.delta}).`,
    );
  }
  if (summary.lean_mass) {
    lines.push(
      `Lean mass ${summary.lean_mass.first} kg to ${summary.lean_mass.last} kg (change ${summary.lean_mass.delta}).`,
    );
  }
  if (summary.weight) {
    lines.push(
      `Weight ${summary.weight.first} kg to ${summary.weight.last} kg (change ${summary.weight.delta}).`,
    );
  }
  return lines.length
    ? lines.join(' ')
    : 'No measurements were available for the confirmed fields.';
}
