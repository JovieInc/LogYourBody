import {
  healthMemoryFailClosed,
  healthMemoryIsolationKey,
  rememberHealthMemory,
  retrieveHealthMemory,
  type HealthMemoryRecord,
} from './health-memory';

const recordedAt = '2026-11-01T00:00:00Z';

function claim(
  userId: string,
  productId: string,
  text: string,
  provenance: HealthMemoryRecord['provenance'] = 'measured',
): HealthMemoryRecord {
  return { userId, productId, text, provenance, recordedAt };
}

describe('health memory isolation', () => {
  it('keeps two users and two products apart and writes nothing when the safety check cannot run', () => {
    expect(healthMemoryIsolationKey).toEqual(['userId', 'productId']);
    expect(healthMemoryFailClosed).toBe('safetyUnavailable');

    expect(rememberHealthMemory([], claim('', 'lyb', '80 kg'), true)).toBeNull();
    expect(rememberHealthMemory([], claim('user-a', '', '80 kg'), true)).toBeNull();
    expect(rememberHealthMemory([], claim('user-a', 'lyb', '   '), true)).toBeNull();
    expect(rememberHealthMemory([], claim('user-a', 'lyb', '80 kg'), false)).toBeNull();

    const userAProductLyb = claim('user-a', 'lyb', '80 kg', 'user-declared');
    const userBProductOther = claim('user-b', 'other', 'secret');
    const stored = rememberHealthMemory(
      rememberHealthMemory([], userAProductLyb, true) ?? [],
      userBProductOther,
      true,
    );
    expect(stored).toEqual([userAProductLyb, userBProductOther]);

    const unavailable = retrieveHealthMemory({
      records: stored ?? [],
      userId: 'user-a',
      productId: 'lyb',
      safetyAvailable: false,
    });
    expect(unavailable).toEqual({ ok: false, reason: healthMemoryFailClosed });
    expect(unavailable).not.toHaveProperty('records');
    expect(JSON.stringify(unavailable)).not.toContain('80 kg');
    expect(JSON.stringify(unavailable)).not.toContain('secret');

    expect(
      retrieveHealthMemory({
        records: stored ?? [],
        userId: 'user-a',
        productId: 'other',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: true, records: [] });
    expect(
      retrieveHealthMemory({
        records: stored ?? [],
        userId: 'user-b',
        productId: 'lyb',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: true, records: [] });
    expect(
      retrieveHealthMemory({
        records: stored ?? [],
        userId: 'user-a',
        productId: 'lyb',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: true, records: [userAProductLyb] });
    expect(
      retrieveHealthMemory({
        records: stored ?? [],
        userId: 'user-b',
        productId: 'other',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: true, records: [userBProductOther] });

    const unchanged = stored ?? [];
    expect(rememberHealthMemory(unchanged, claim('user-a', 'lyb', 'leaked'), false)).toBeNull();
    expect(unchanged).toEqual([userAProductLyb, userBProductOther]);
    expect(
      retrieveHealthMemory({
        records: unchanged,
        userId: '',
        productId: 'lyb',
        safetyAvailable: true,
      }),
    ).toEqual({ ok: false, reason: 'isolated' });
  });
});
