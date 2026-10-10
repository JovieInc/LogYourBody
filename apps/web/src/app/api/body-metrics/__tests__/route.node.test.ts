/** @jest-environment node */

import { NextRequest } from 'next/server';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { POST } from '../route';

jest.mock('@/lib/neon/body-metrics-adapter', () => ({ neonBodyMetrics: { upsert: jest.fn() } }));
jest.mock('@/lib/ports/server-auth-runtime', () => ({ getServerAuthSession: jest.fn() }));

const mockedMetrics = jest.mocked(neonBodyMetrics);
const mockedAuth = jest.mocked(getServerAuthSession);

function request(body: unknown) {
  return new NextRequest('http://localhost/api/body-metrics', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('/api/body-metrics', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedAuth.mockResolvedValue({ userId: 'jovie-user-1', getToken: jest.fn() });
  });

  it('rejects unauthenticated writes', async () => {
    mockedAuth.mockResolvedValue({ userId: null, getToken: jest.fn() });
    expect((await POST(request({ date: '2026-07-15' }))).status).toBe(401);
  });

  it('validates and maps the app contract to the Neon port', async () => {
    mockedMetrics.upsert.mockResolvedValue({ id: 'metric-1' } as never);
    const response = await POST(
      request({
        date: '2026-07-15',
        weight: 80,
        weightUnit: 'kg',
        bodyFatPercentage: 18,
        bodyFatMethod: 'dexa',
        dataSource: 'bodyspec_dexa',
      }),
    );
    expect(response.status).toBe(201);
    expect(mockedMetrics.upsert).toHaveBeenCalledWith('jovie-user-1', {
      date: '2026-07-15',
      weight: 80,
      weight_unit: 'kg',
      body_fat_percentage: 18,
      body_fat_method: 'dexa',
      muscle_mass: null,
      waist: null,
      neck: null,
      hip: null,
      notes: null,
      photo_url: null,
      data_source: 'bodyspec_dexa',
      source_metadata: {},
    });
  });

  it.each([
    'manual',
    'healthkit',
    'smart_scale',
    'bodyspec_dexa',
    'dexa_pdf',
    'inbody_pdf',
    'caliper',
    'photo',
  ] as const)('retains support for source %s', async (dataSource) => {
    mockedMetrics.upsert.mockResolvedValue({ id: 'metric-1' } as never);
    const response = await POST(
      request({ date: '2026-09-20', weight: 80, weightUnit: 'kg', dataSource }),
    );
    expect(response.status).toBe(201);
    expect(mockedMetrics.upsert).toHaveBeenCalledWith(
      'jovie-user-1',
      expect.objectContaining({ data_source: dataSource }),
    );
  });
  it('accepts explicit unknown-method PDF provenance without inventing a measurement method', async () => {
    const sourceMetadata = { vendor: 'pdf_import', source_name: 'Unidentified device' };
    mockedMetrics.upsert.mockResolvedValue({ id: 'metric-pdf' } as never);
    const response = await POST(
      request({
        date: '2026-10-09',
        weight: 80,
        weightUnit: 'kg',
        dataSource: 'pdf_import',
        sourceMetadata,
      }),
    );
    expect(response.status).toBe(201);
    expect(mockedMetrics.upsert).toHaveBeenCalledWith(
      'jovie-user-1',
      expect.objectContaining({
        data_source: 'pdf_import',
        source_metadata: sourceMetadata,
        body_fat_method: null,
        muscle_mass: null,
      }),
    );
  });

  it.each(['unknown', 'PDF Import', ''])(
    'does not accept noncanonical source %j',
    async (dataSource) => {
      const response = await POST(request({ date: '2026-10-09', weight: 80, dataSource }));
      expect(response.status).toBe(400);
      expect(mockedMetrics.upsert).not.toHaveBeenCalled();
    },
  );

  it('preserves the manual default when no source is supplied', async () => {
    mockedMetrics.upsert.mockResolvedValue({ id: 'metric-manual' } as never);
    expect((await POST(request({ date: '2026-10-09', weight: 80 }))).status).toBe(201);
    expect(mockedMetrics.upsert).toHaveBeenCalledWith(
      'jovie-user-1',
      expect.objectContaining({
        data_source: 'manual',
        source_metadata: {},
      }),
    );
  });
});
