/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createNativeProductRecordHandlers } from '@/app/api/auth/mobile/sync/v1/[collection]/route-handlers';
import { createNativeBodyMetricsSyncHandlers } from '@/app/api/auth/mobile/sync/v1/body-metrics/route-handlers';
import {
  NativeAccountAdmissionError,
  type NativeAccountAdmission,
} from '@/lib/ports/native-account-admission';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import type { NativeBodyMetricsSyncPort } from '@/lib/ports/native-body-metrics-sync';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const subject = 'native-account-owner';
const bodyRecord = {
  id: A,
  date: '2026-10-10T10:00:00Z',
  local_date: '2026-10-10',
  weight: 80,
  weight_unit: 'kg',
  waist_circumference: null,
  hip_circumference: null,
  waist_unit: 'cm',
  body_fat_percentage: null,
  body_fat_method: null,
  muscle_mass: null,
  bone_mass: null,
  photo_url: null,
  notes: 'unchanged',
  data_source: 'manual',
  source_metadata: {},
  created_at: '2026-10-10T10:00:00Z',
  updated_at: '2026-10-10T10:00:00Z',
};
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
const operations = [
  ['generic push', 'daily-metrics', 'POST', { records: [{ id: A, steps: 100 }] }],
  ['generic remove', 'daily-metrics', 'DELETE', { ids: [A] }],
  ['medication completion', 'glp1-medications', 'POST', { ended_at: '2026-10-10T10:00:00Z' }],
  ['body push', 'body-metrics', 'POST', { records: [bodyRecord] }],
  ['body remove', 'body-metrics', 'DELETE', { ids: [A] }],
] as const;
function harness() {
  let owner: string | null = A;
  const writes: unknown[] = [];
  const capture = jest.fn(async () => (owner ? Object.freeze({ subject, ownerId: owner }) : null));
  const admit = (a: NativeAccountAdmission) => {
    if (a.subject !== subject || a.ownerId !== owner)
      throw new NativeAccountAdmissionError('account_changed');
  };
  const write = async (...value: unknown[]) => {
    writes.push(value);
    return { records: [], rejected_ids: [], deleted_ids: [], updated: 1 };
  };
  const records = {
    push: write,
    remove: write,
    endActiveGlp1Medications: write,
    pull: jest.fn(),
    listAll: jest.fn(),
    deleteAllForSubject: jest.fn(),
    accountMutations: {
      capture,
      push: async (a: NativeAccountAdmission, ...v: unknown[]) => {
        admit(a);
        return write(...v);
      },
      remove: async (a: NativeAccountAdmission, ...v: unknown[]) => {
        admit(a);
        return write(...v);
      },
      endActiveGlp1Medications: async (a: NativeAccountAdmission, ...v: unknown[]) => {
        admit(a);
        return write(...v);
      },
    },
  } as NativeProductRecordsPort;
  const sync = {
    push: write,
    remove: write,
    pull: jest.fn(),
    accountMutations: records.accountMutations,
  } as unknown as NativeBodyMetricsSyncPort;
  const authenticate = jest.fn(async () => ({ sub: subject }));
  const generic = createNativeProductRecordHandlers({ authenticate, records });
  const body = createNativeBodyMetricsSyncHandlers({ authenticate, sync });
  return {
    capture,
    records,
    sync,
    authenticate,
    writes,
    setOwner: (value: string | null) => {
      owner = value;
    },
    call: (path: string, method: 'POST' | 'DELETE', request: NextRequest) =>
      (path === 'body-metrics' ? body : generic)[method](request),
  };
}

describe('native account request admission', () => {
  it.each(operations)(
    '%s rejects a held body after account deletion',
    async (_, path, method, payload) => {
      const h = harness();
      const entered = deferred<void>();
      const release = deferred<unknown>();
      const req = new NextRequest(`http://localhost/api/auth/mobile/sync/v1/${path}`, { method });
      jest.spyOn(req, 'json').mockImplementation(() => {
        entered.resolve();
        return release.promise;
      });
      const pending = h.call(path, method, req);
      await entered.promise;
      h.setOwner(null);
      release.resolve(payload);
      const response = await pending;
      expect(response.status).toBe(409);
      expect(await response.json()).toMatchObject({ error: 'account_changed' });
      expect(h.writes).toEqual([]);
      expect(h.capture).toHaveBeenCalledTimes(1);
    },
  );
  it.each(operations)(
    '%s does not adopt a recreated same-subject account',
    async (_, path, method, payload) => {
      const h = harness();
      const entered = deferred<void>();
      const release = deferred<unknown>();
      const req = new NextRequest(`http://localhost/api/auth/mobile/sync/v1/${path}`, { method });
      jest.spyOn(req, 'json').mockImplementation(() => {
        entered.resolve();
        return release.promise;
      });
      const pending = h.call(path, method, req);
      await entered.promise;
      h.setOwner(B);
      release.resolve(payload);
      const response = await pending;
      expect(response.status).toBe(409);
      expect(h.writes).toEqual([]);
      expect(h.capture).toHaveBeenCalledTimes(1);
    },
  );
  it.each(operations)(
    '%s rejects missing owners and unsupported ports without body reads or fallback',
    async (_, path, method, payload) => {
      const h = harness();
      h.setOwner(null);
      const request = () =>
        new NextRequest(`http://localhost/api/auth/mobile/sync/v1/${path}`, {
          method,
          body: JSON.stringify(payload),
        });
      const req = request();
      const read = jest.spyOn(req, 'json');
      expect((await h.call(path, method, req)).status).toBe(404);
      expect(read).not.toHaveBeenCalled();
      delete h.records.accountMutations;
      delete h.sync.accountMutations;
      expect((await h.call(path, method, request())).status).toBe(503);
      expect(h.writes).toEqual([]);
    },
  );
  it('documents the bearer-only boundary: auth completed after recreation captures the current account', async () => {
    const h = harness();
    const auth = deferred<{ sub: string }>();
    h.authenticate.mockReturnValueOnce(auth.promise);
    const req = new NextRequest('http://localhost/api/auth/mobile/sync/v1/daily-metrics', {
      method: 'POST',
      body: JSON.stringify({ records: [{ id: A, steps: 100 }] }),
    });
    const pending = h.call('daily-metrics', 'POST', req);
    h.setOwner(B);
    auth.resolve({ sub: subject });
    expect((await pending).status).toBe(200);
    expect(h.capture).toHaveBeenCalledTimes(1);
    expect(h.writes).toHaveLength(1);
  });
});
