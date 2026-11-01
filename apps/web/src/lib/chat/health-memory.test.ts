import {
  rememberHealthMemory,
  retrieveHealthMemory,
  type HealthMemoryRecord,
} from './health-memory';

const measured: HealthMemoryRecord = {
  userId: 'user-a',
  productId: 'lyb',
  text: '80 kg',
  provenance: 'user-declared',
  recordedAt: '2026-11-01T00:00:00Z',
};

describe('health memory isolation', () => {
  it('keeps records on one user and product and fails closed without a safety check', () => {
    expect(rememberHealthMemory([], { ...measured, userId: '' })).toBeNull();
    expect(rememberHealthMemory([], { ...measured, productId: 'other' as 'lyb' })).toBeNull();
    expect(rememberHealthMemory([], { ...measured, text: '   ' })).toBeNull();
    const stored = rememberHealthMemory([], measured);
    const withOther = rememberHealthMemory(stored ?? [], {
      ...measured,
      userId: 'user-b',
      text: 'secret',
      provenance: 'measured',
    });
    expect(
      retrieveHealthMemory({
        records: withOther ?? [],
        userId: 'user-a',
        productId: 'lyb',
        safetyAvailable: false,
      }),
    ).toEqual({ ok: false, reason: 'safetyUnavailable' });
    expect(
      retrieveHealthMemory({
        records: withOther ?? [],
        userId: 'user-a',
        productId: 'other',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: false, reason: 'isolated' });
    expect(
      retrieveHealthMemory({
        records: withOther ?? [],
        userId: 'user-a',
        productId: 'lyb',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: true, records: [measured] });
  });
});
