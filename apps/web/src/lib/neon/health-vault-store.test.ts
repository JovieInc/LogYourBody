/** @jest-environment node */

jest.mock('server-only', () => ({}));

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonHealthVaultStore } from './health-vault-store';

function databaseWith(query: jest.Mock) {
  return { query } as unknown as NeonQueryFunction<false, false>;
}

function normalized(statement: unknown) {
  return String(statement).replace(/\s+/g, ' ').trim();
}

describe('createNeonHealthVaultStore', () => {
  it('stores consent field names and not measurement values', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonHealthVaultStore(databaseWith(query));

    await store.putGrant({
      hash: 'hash-1',
      subject: 'subject-a',
      kind: 'consent',
      expiresAtMs: Date.parse('2026-03-01T00:05:00.000Z'),
      fields: ['body_fat'],
    });

    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'insert into public.health_vault_grants',
    );
    expect(query.mock.calls[0]?.[1]?.[4]).toBe(JSON.stringify({ fields: ['body_fat'] }));
    expect(String(query.mock.calls[0]?.[1]?.[4])).not.toContain('17.3417');
  });

  it('deletes a grant and returns null once it is expired', async () => {
    const query = jest.fn().mockResolvedValue([
      {
        token_hash: 'hash-1',
        user_subject: 'subject-a',
        kind: 'view',
        expires_at: '2026-01-01T00:00:00.000Z',
        payload: {},
      },
    ]);
    const store = createNeonHealthVaultStore(databaseWith(query));

    await expect(
      store.takeGrant('hash-1', 'view', new Date('2026-03-01T00:00:00.000Z')),
    ).resolves.toBeNull();
    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'delete from public.health_vault_grants',
    );
  });

  it('reads unexpired media without deleting the row', async () => {
    const query = jest.fn().mockResolvedValue([
      {
        token_hash: 'hash-1',
        user_subject: 'subject-a',
        kind: 'media',
        expires_at: '2026-04-01T00:00:00.000Z',
        payload: {
          contentType: 'image/png',
          bodyBase64: Buffer.from('png-bytes').toString('base64'),
        },
      },
    ]);
    const store = createNeonHealthVaultStore(databaseWith(query));

    const media = await store.readMedia('hash-1', new Date('2026-03-01T00:00:00.000Z'));

    expect(media?.contentType).toBe('image/png');
    expect(Buffer.from(media?.bytes ?? []).toString()).toBe('png-bytes');
    expect(normalized(query.mock.calls[0]?.[0])).toContain("kind = 'media'");
    expect(normalized(query.mock.calls[0]?.[0])).not.toContain('delete');
  });

  it('appends a consent event with field names only', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonHealthVaultStore(databaseWith(query));

    await store.appendConsent({
      subject: 'subject-a',
      consentId: 'co_consent',
      fields: ['weight'],
      at: '2026-03-01T00:00:00.000Z',
    });

    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'insert into public.health_vault_consent_log',
    );
    expect(query.mock.calls[0]?.[1]).toEqual([
      'subject-a',
      'co_consent',
      JSON.stringify(['weight']),
    ]);
  });

  it('keeps only known share fields from a stored payload', async () => {
    const query = jest.fn().mockResolvedValue([
      {
        token_hash: 'hash-1',
        user_subject: 'subject-a',
        kind: 'consent',
        expires_at: '2026-04-01T00:00:00.000Z',
        payload: JSON.stringify({
          fields: ['body_fat', 'photo', 'weight'],
          bodyFatPercent: 17.3417,
        }),
      },
    ]);
    const store = createNeonHealthVaultStore(databaseWith(query));

    const grant = await store.takeGrant('hash-1', 'consent', new Date('2026-03-01T00:00:00.000Z'));

    expect(grant?.fields).toEqual(['body_fat', 'weight']);
  });
});
