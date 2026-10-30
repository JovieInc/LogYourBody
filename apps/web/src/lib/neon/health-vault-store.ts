import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import {
  tokenHash,
  type ConsentEvent,
  type GrantKind,
  type HealthVaultSessionStore,
  type StoredGrant,
  type StoredMedia,
} from '@/lib/mcp/health-vault/session-store';
import type { ShareField } from '@/lib/mcp/health-vault/types';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

type GrantRow = {
  token_hash: string;
  user_subject: string;
  kind: GrantKind;
  expires_at: string | Date;
  payload: { fields?: ShareField[]; contentType?: string; bodyBase64?: string } | string | null;
};

function payloadOf(value: GrantRow['payload']): GrantRow['payload'] {
  if (typeof value === 'string') {
    try {
      return JSON.parse(value) as GrantRow['payload'];
    } catch {
      return null;
    }
  }
  return value;
}

function mapGrant(row: GrantRow): StoredGrant {
  const payload = payloadOf(row.payload);
  const fields =
    payload && typeof payload === 'object' && Array.isArray(payload.fields)
      ? payload.fields.filter(
          (field): field is ShareField =>
            field === 'lean_mass' || field === 'body_fat' || field === 'weight',
        )
      : undefined;
  return {
    hash: row.token_hash,
    subject: row.user_subject,
    kind: row.kind,
    expiresAtMs: new Date(row.expires_at).getTime(),
    ...(fields?.length ? { fields } : {}),
  };
}

export function createNeonHealthVaultStore(
  database?: NeonQueryFunction<false, false>,
): HealthVaultSessionStore {
  const db = () => database ?? getDatabase();
  return {
    async putGrant(grant) {
      await db().query(
        `insert into public.health_vault_grants
           (token_hash, user_subject, kind, expires_at, payload)
         values ($1, $2, $3, $4, $5::jsonb)`,
        [
          grant.hash,
          grant.subject,
          grant.kind,
          new Date(grant.expiresAtMs).toISOString(),
          JSON.stringify(grant.fields ? { fields: grant.fields } : {}),
        ],
      );
    },

    async takeGrant(hash, kind, now) {
      const rows = (await db().query(
        `delete from public.health_vault_grants
         where token_hash = $1 and kind = $2
         returning token_hash, user_subject, kind, expires_at, payload`,
        [hash, kind],
      )) as GrantRow[];
      const grant = rows[0] ? mapGrant(rows[0]) : null;
      if (!grant || grant.expiresAtMs <= now.getTime()) return null;
      return grant;
    },

    async putMedia(media: StoredMedia) {
      await db().query(
        `insert into public.health_vault_grants
           (token_hash, user_subject, kind, expires_at, payload)
         values ($1, $2, 'media', $3, $4::jsonb)`,
        [
          media.hash,
          media.subject,
          new Date(media.expiresAtMs).toISOString(),
          JSON.stringify({
            contentType: media.contentType,
            bodyBase64: Buffer.from(media.bytes).toString('base64'),
          }),
        ],
      );
    },

    async readMedia(hash, now) {
      const rows = (await db().query(
        `select token_hash, user_subject, kind, expires_at, payload
         from public.health_vault_grants
         where token_hash = $1 and kind = 'media' and expires_at > $2`,
        [hash, now.toISOString()],
      )) as GrantRow[];
      const row = rows[0];
      if (!row) return null;
      const payload = payloadOf(row.payload);
      if (!payload || typeof payload !== 'object' || !payload.contentType || !payload.bodyBase64) {
        return null;
      }
      return {
        hash: row.token_hash,
        subject: row.user_subject,
        expiresAtMs: new Date(row.expires_at).getTime(),
        contentType: payload.contentType,
        bytes: Buffer.from(payload.bodyBase64, 'base64'),
      };
    },

    async appendConsent(event: ConsentEvent) {
      await db().query(
        `insert into public.health_vault_consent_log (user_subject, consent_id, fields)
         values ($1, $2, $3::jsonb)`,
        [event.subject, event.consentId, JSON.stringify(event.fields)],
      );
    },
  };
}

export function healthVaultMediaReader(
  store: HealthVaultSessionStore,
  now: () => Date,
): { read(token: string): Promise<StoredMedia | null> } {
  return {
    read(token: string) {
      return store.readMedia(tokenHash(token), now());
    },
  };
}
