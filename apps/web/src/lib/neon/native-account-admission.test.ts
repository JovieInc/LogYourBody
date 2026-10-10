/** @jest-environment node */
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonNativeProductRecords } from './native-product-records-adapter';
import { createNeonNativeBodyMetricsSync } from './native-body-metrics-sync-adapter';
import { captureNativeAccountAdmission } from './native-account-admission';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';
import type { NativeBodyMetricPushInput } from '@/lib/ports/native-body-metrics-sync';
const admission = { subject: 'owner', ownerId: '11111111-1111-4111-8111-111111111111' };
const id = '22222222-2222-4222-8222-222222222222';
function db() {
  const query = jest.fn((text: string, params: unknown[]) => ({ text, params }));
  const transaction = jest.fn().mockResolvedValue([[], [], []]);
  return {
    query,
    transaction,
    database: { query, transaction } as unknown as NeonQueryFunction<false, false>,
  };
}
it('captures the physical UUID immutably and never caches admission across calls', async () => {
  const query = jest
    .fn()
    .mockResolvedValueOnce([{ id: admission.ownerId }])
    .mockResolvedValueOnce([]);
  const database = { query } as unknown as NeonQueryFunction<false, false>;
  const captured = await captureNativeAccountAdmission(database, admission.subject);
  expect(captured).toEqual(admission);
  expect(Object.isFrozen(captured)).toBe(true);
  expect(await captureNativeAccountAdmission(database, admission.subject)).toBeNull();
  expect(query).toHaveBeenCalledTimes(2);
});
it('does not accept malformed owner metadata as admission', async () => {
  const database = {
    query: jest.fn().mockResolvedValue([{ id: 'not-a-uuid' }]),
  } as unknown as NeonQueryFunction<false, false>;
  await expect(captureNativeAccountAdmission(database, 'owner')).rejects.toEqual(
    new NativeAccountAdmissionError('account_admission_unavailable'),
  );
});
it('sends one guard-first transaction for the complete generic batch and preserves typed omission', async () => {
  const h = db();
  const port = createNeonNativeProductRecords(h.database).accountMutations!;
  const result = await port.push(admission, 'dexa_results', [
    { id, notes: 'legacy' },
    { id: admission.ownerId, reported_measurements: { schema_version: 1, items: [] } },
  ]);
  expect(h.transaction).toHaveBeenCalledTimes(1);
  const queries = h.transaction.mock.calls[0]![0];
  expect(queries[0]).toEqual({
    text: 'select public.lyb_native_account_admit($1, $2::uuid)',
    params: [admission.subject, admission.ownerId],
  });
  expect(queries).toHaveLength(3);
  expect(JSON.parse(queries[1].params[3])).toEqual({ id, notes: 'legacy' });
  expect(JSON.parse(queries[2].params[3]).reported_measurements).toEqual({
    schema_version: 1,
    items: [],
  });
  expect(result.rejected_ids).toEqual([id, admission.ownerId]);
});
it('body batches, tombstones and medication completion all use the same guard', async () => {
  const h = db();
  h.transaction.mockResolvedValue([[], []]);
  const body = createNeonNativeBodyMetricsSync(h.database).accountMutations!;
  await body.push(admission, [{ id, source_metadata: {} } as NativeBodyMetricPushInput]);
  await body.remove(admission, [id]);
  const native = createNeonNativeProductRecords(h.database).accountMutations!;
  await native.remove(admission, 'daily_metrics', [id]);
  await native.endActiveGlp1Medications(admission, '2026-10-10T12:00:00Z');
  expect(h.transaction).toHaveBeenCalledTimes(4);
  for (const [queries] of h.transaction.mock.calls) {
    expect(queries).toHaveLength(2);
    expect(queries[0].params).toEqual([admission.subject, admission.ownerId]);
    expect(queries[0].text).toContain('lyb_native_account_admit');
  }
});
it.each([
  ['LYB01', 'account_changed'],
  ['42883', 'account_admission_unavailable'],
])(
  'maps %s without returning successful record acknowledgements or fallback',
  async (code, message) => {
    const h = db();
    h.transaction.mockRejectedValue(Object.assign(new Error('private database detail'), { code }));
    const port = createNeonNativeProductRecords(h.database).accountMutations!;
    await expect(port.push(admission, 'daily_metrics', [{ id }])).rejects.toMatchObject({
      message,
    });
    expect(h.transaction).toHaveBeenCalledTimes(1);
    expect(h.query).toHaveBeenCalledTimes(2); // one lazy write plus guard; never a fallback write
  },
);
it('invalid captured UUID fails before any transaction executes', async () => {
  const h = db();
  const port = createNeonNativeProductRecords(h.database).accountMutations!;
  await expect(
    port.remove({ ...admission, ownerId: '' }, 'daily_metrics', [id]),
  ).rejects.toMatchObject({ code: 'account_changed' });
  expect(h.transaction).not.toHaveBeenCalled();
});
