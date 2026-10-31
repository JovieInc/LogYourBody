/** @jest-environment node */

import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonBodyMetrics, neonBodyMetricsExport } from '@/lib/neon/body-metrics-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { GET, POST } from '../route';
import { neonTrainingRevisions } from '@/lib/neon/training-revisions-adapter';
const outcomeRead = jest.fn();
const outcomeExport = jest.fn();
jest.mock('@/lib/neon/dated-outcome-adapter', () => ({
  neonDatedOutcomes: () => ({ read: outcomeRead, exportForSubject: outcomeExport }),
}));
jest.mock('@/lib/neon/training-revisions-adapter', () => ({
  neonTrainingRevisions: { exportForSubject: jest.fn() },
}));

jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));
jest.mock('@/lib/neon/body-metrics-adapter', () => ({
  neonBodyMetrics: { list: jest.fn() },
  neonBodyMetricsExport: { listAll: jest.fn() },
}));
jest.mock('@/lib/neon/native-product-records-adapter', () => ({
  neonNativeProductRecords: { listAll: jest.fn() },
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { getUser: jest.fn() },
}));

const mockedFetchUserInfo = jest.mocked(fetchUserInfo);
const mockedMetrics = jest.mocked(neonBodyMetricsExport);
const mockedHistory = jest.mocked(neonBodyMetrics);
const mockedRecords = jest.mocked(neonNativeProductRecords);
const mockedDirectory = jest.mocked(neonUserDirectory);

function request(method: 'GET' | 'POST', token?: string) {
  return new NextRequest('http://localhost/api/auth/mobile/export', {
    method,
    headers: token ? { authorization: `Bearer ${token}` } : undefined,
  });
}

describe('/api/auth/mobile/export', () => {
  beforeEach(() => {
    jest.resetAllMocks();
    outcomeRead.mockResolvedValue({
      revision: 'outcome-revision',
      value: { outcomeDate: '2027-04-01' },
    });
    outcomeExport.mockResolvedValue([{ request_id: 'outcome-revision' }]);
    jest
      .mocked(neonTrainingRevisions.exportForSubject)
      .mockResolvedValue({ proposals: [], revisions: [{ id: 'revision-owned' }] });
  });

  it('rejects missing bearer tokens and cookies before reading Neon', async () => {
    expect((await GET(request('GET'))).status).toBe(401);
    expect(mockedDirectory.getUser).not.toHaveBeenCalled();
  });

  it('accepts the first-party session cookie when no bearer token is present', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedDirectory.getUser.mockResolvedValue({ subject: 'owner-a' } as never);
    mockedMetrics.listAll.mockResolvedValue([]);
    mockedRecords.listAll.mockResolvedValue({
      daily_metrics: [],
      glp1_medications: [],
      glp1_dose_logs: [],
      dexa_results: [],
      progress_photos: [],
      training_sessions: [],
      logged_sets: [],
      training_feedback: [],
    } as never);

    const response = await GET(
      new NextRequest('http://localhost/api/auth/mobile/export', {
        headers: { cookie: 'lyb_access_token=cookie-a' },
      }),
    );
    expect(response.status).toBe(200);
    expect(mockedFetchUserInfo).toHaveBeenCalledWith('cookie-a');
    expect(mockedDirectory.getUser).toHaveBeenCalledWith('owner-a');
  });

  it('dumps the authenticated subject Neon rows without a legacy provider path', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedDirectory.getUser.mockResolvedValue({
      subject: 'owner-a',
      email: 'a@example.com',
    } as never);
    mockedMetrics.listAll.mockResolvedValue([{ id: 'metric-1' }] as never);
    mockedRecords.listAll.mockResolvedValue({
      daily_metrics: [{ id: 'daily-1' }],
      glp1_medications: [],
      glp1_dose_logs: [],
      dexa_results: [],
      progress_photos: [],
      training_sessions: [],
      logged_sets: [],
      training_feedback: [],
    } as never);

    const response = await POST(request('POST', 'access-a'));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      version: 1,
      subject: 'owner-a',
      profile: { subject: 'owner-a' },
      dated_outcome: { revision: 'outcome-revision', value: { outcomeDate: '2027-04-01' } },
      dated_outcome_recompute_requests: [{ request_id: 'outcome-revision' }],
      body_metrics: [{ id: 'metric-1' }],
      training_program_revisions: { proposals: [], revisions: [{ id: 'revision-owned' }] },
      daily_metrics: [{ id: 'daily-1' }],
    });
    expect(mockedMetrics.listAll).toHaveBeenCalledWith('owner-a');
    expect(mockedRecords.listAll).toHaveBeenCalledWith('owner-a');
    expect(neonTrainingRevisions.exportForSubject).toHaveBeenCalledWith('owner-a');
  });

  it.each(['GET', 'POST'] as const)(
    'exports more than 100 rows through %s without losing the final record',
    async (method) => {
      const metrics = Array.from({ length: 137 }, (_, index) => ({
        id: `metric-${index}`,
        photo_url: index === 136 ? 'https://example.com/last-photo.jpg' : null,
        source_metadata: { provider: 'fixture', original: { value: index, unit: 'kg' } },
      }));
      mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
      mockedDirectory.getUser.mockResolvedValue({ subject: 'owner-a' } as never);
      mockedHistory.list.mockResolvedValue(metrics.slice(0, 100) as never);
      mockedMetrics.listAll.mockResolvedValue(metrics as never);
      mockedRecords.listAll.mockResolvedValue({
        daily_metrics: [],
        glp1_medications: [],
        glp1_dose_logs: [],
        dexa_results: [],
        progress_photos: [],
        training_sessions: [],
        logged_sets: [],
        training_feedback: [],
      });

      const response = await (method === 'GET' ? GET : POST)(request(method, 'access-a'));
      expect(response.status).toBe(200);
      expect(response.headers.get('Cache-Control')).toBe('no-store');
      const body = await response.json();
      expect(body.version).toBe(1);
      expect(body.subject).toBe('owner-a');
      expect(body.body_metrics).toEqual(metrics);
      expect(body.body_metrics.at(-1)).toEqual(metrics[136]);
      expect(mockedHistory.list).not.toHaveBeenCalled();
      expect(mockedMetrics.listAll).toHaveBeenCalledWith('owner-a');
      expect(mockedRecords.listAll).toHaveBeenCalledWith('owner-a');
    },
  );

  it('does not return a partial successful export when a collection read fails', async () => {
    mockedFetchUserInfo.mockResolvedValue({ sub: 'owner-a' } as never);
    mockedDirectory.getUser.mockResolvedValue({ subject: 'owner-a' } as never);
    mockedMetrics.listAll.mockResolvedValue([]);
    mockedRecords.listAll.mockRejectedValue(new Error('record read failed'));
    await expect(GET(request('GET', 'access-a'))).rejects.toThrow('record read failed');
  });
});
