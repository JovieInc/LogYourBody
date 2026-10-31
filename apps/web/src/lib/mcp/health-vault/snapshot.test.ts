/** @jest-environment node */

import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { createProductVaultReader } from './reader';
import { snapshotFromSources } from './snapshot';

const ORIGINS = ['https://www.logyourbody.com', 'https://photos.logyourbody.com'];

function metric(
  partial: Partial<ProductBodyMetric> & Pick<ProductBodyMetric, 'id' | 'date'>,
): ProductBodyMetric {
  return {
    user_subject: 'subject-a',
    weight: null,
    weight_unit: 'kg',
    body_fat_percentage: null,
    body_fat_method: null,
    muscle_mass: null,
    waist: null,
    neck: null,
    hip: null,
    notes: null,
    photo_url: null,
    data_source: 'manual',
    source_metadata: {},
    created_at: partial.date,
    updated_at: partial.date,
    ...partial,
  };
}

function record(
  id: string,
  fields: Record<string, unknown>,
  deleted_at: string | null = null,
): NativeProductRecord {
  return { id, deleted_at, server_updated_at: '2026-01-01T00:00:00.000Z', ...fields };
}

describe('snapshotFromSources', () => {
  it('maps scans, allowlisted photos, and kilogram weigh-ins', () => {
    const snapshot = snapshotFromSources({
      dexaRecords: [
        record(
          'old',
          { body_fat_percentage: 20, muscle_mass: 50, acquire_time: '2026-01-01' },
          '2026-01-02',
        ),
        record('dx', {
          body_fat_percentage: '17.5',
          muscle_mass: 60.5,
          acquire_time: '2026-02-01T08:00:00Z',
        }),
      ],
      photoRecords: [
        record('foreign', { image_url: 'https://evil.example/secret.png' }),
        record('local-only', { url: null }),
        record('ok', { photo_url: 'https://photos.logyourbody.com/a.jpg' }),
        record('script', { url: 'javascript:alert(1)' }),
      ],
      bodyMetrics: [
        metric({
          id: 'bf',
          date: '2026-01-15',
          body_fat_percentage: 18,
          body_fat_method: 'dexa',
          muscle_mass: 59,
          weight: 80,
          weight_unit: 'kg',
          photo_url: 'https://www.logyourbody.com/photos/1.jpg',
        }),
        metric({
          id: 'lbs',
          date: '2026-03-01',
          weight: 100,
          weight_unit: 'lbs',
          data_source: 'manual',
        }),
        metric({
          id: 'other-unit',
          date: '2026-03-02',
          weight: 70,
          weight_unit: 'st' as 'kg',
        }),
      ],
      allowedOrigins: ORIGINS,
    });

    expect(snapshot.dexa.map((row) => row.id)).toEqual(['bf', 'dx']);
    expect(snapshot.dexa[1]).toMatchObject({
      bodyFatPercent: 17.5,
      leanMassKg: 60.5,
      measuredOn: '2026-02-01',
    });
    expect(snapshot.photos.map((row) => [row.id, row.imageUrl])).toEqual([
      ['bf', 'https://www.logyourbody.com/photos/1.jpg'],
      ['foreign', null],
      ['local-only', null],
      ['ok', 'https://photos.logyourbody.com/a.jpg'],
      ['script', null],
    ]);
    expect(snapshot.weighIns).toEqual([
      { id: 'bf', measuredOn: '2026-01-15', weightKg: 80 },
      { id: 'lbs', measuredOn: '2026-03-01', weightKg: 45.359237 },
    ]);
  });

  it('keeps a localhost photo only when that origin is allowed', () => {
    const photo = record('p', { photo_url: 'http://localhost:3000/a.jpg' });
    expect(
      snapshotFromSources({
        dexaRecords: [],
        photoRecords: [photo],
        bodyMetrics: [],
        allowedOrigins: ['http://localhost:3000'],
      }).photos,
    ).toEqual([{ id: 'p', imageUrl: 'http://localhost:3000/a.jpg' }]);
    expect(
      snapshotFromSources({
        dexaRecords: [],
        photoRecords: [photo],
        bodyMetrics: [],
        allowedOrigins: ORIGINS,
      }).photos,
    ).toEqual([{ id: 'p', imageUrl: null }]);
  });
});

describe('createProductVaultReader', () => {
  it('reads scans and photos and skips other collections', async () => {
    const reader = createProductVaultReader({
      records: {
        async listAll() {
          return {
            dexa_results: [record('dx', { body_fat_percentage: 11, acquire_time: '2026-01-02' })],
            progress_photos: [record('ph1', { photo_url: 'https://photos.logyourbody.com/a.jpg' })],
            glp1_dose_logs: [
              record('ph_SENTINEL', {
                photo_url: 'https://photos.logyourbody.com/secret.jpg',
                body_fat_percentage: 17.3417,
              }),
            ],
          } as Awaited<ReturnType<NativeProductRecordsPort['listAll']>>;
        },
      },
      bodyMetrics: {
        async listAll() {
          return [
            metric({
              id: 'w',
              date: '2026-02-02',
              weight: 81,
              weight_unit: 'kg',
              data_source: 'bodyspec_dexa',
              body_fat_percentage: 12,
            }),
          ];
        },
      },
      apiOrigin: 'https://www.logyourbody.com',
    });

    const snapshot = await reader.read('subject-a');

    expect(snapshot.dexa.map((row) => row.id).sort()).toEqual(['dx', 'w']);
    expect(snapshot.photos.map((row) => row.id)).toEqual(['ph1']);
    expect(JSON.stringify(snapshot)).not.toContain('ph_SENTINEL');
    expect(JSON.stringify(snapshot)).not.toContain('17.3417');
  });
});
