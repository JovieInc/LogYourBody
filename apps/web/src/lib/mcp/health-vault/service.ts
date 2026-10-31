import {
  HEALTH_VAULT_SHARE_FIELDS,
  type HealthVaultReader,
  type HealthVaultService,
  type ShareField,
  type VaultPhoto,
} from './types';
import { HEALTH_VAULT_VIEW_TTL_MS, vaultConnectOrigins } from './constants';
import { summarizeVault } from './snapshot';
import { newOpaqueToken, tokenHash, type HealthVaultSessionStore } from './session-store';
import { isVaultAssetUrl } from './urls';

const MEDIA_BYTE_LIMIT = 65_536;
const MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export function createHealthVaultService(input: {
  reader: HealthVaultReader;
  store: HealthVaultSessionStore;
  now: () => Date;
}): HealthVaultService {
  const expiresAt = () => input.now().getTime() + HEALTH_VAULT_VIEW_TTL_MS;

  async function mediaUrl(
    photo: VaultPhoto,
    subject: string,
    apiOrigin: string,
  ): Promise<string | null> {
    if (photo.imageUrl && isVaultAssetUrl(photo.imageUrl, vaultConnectOrigins(apiOrigin))) {
      return photo.imageUrl;
    }
    if (!photo.bytes || photo.bytes.byteLength === 0 || photo.bytes.byteLength > MEDIA_BYTE_LIMIT) {
      return null;
    }
    const contentType = photo.contentType ?? 'image/jpeg';
    if (!MEDIA_TYPES.has(contentType)) return null;
    const token = newOpaqueToken('md');
    await input.store.putMedia({
      hash: tokenHash(token),
      subject,
      expiresAtMs: expiresAt(),
      contentType,
      bytes: photo.bytes,
    });
    return `${apiOrigin}/api/health-vault/media?token=${encodeURIComponent(token)}`;
  }

  return {
    async open(subject) {
      // Handle and counts only. Measurements come from redeem() and from share() after confirm.
      try {
        const snapshot = await input.reader.read(subject);
        const handle = newOpaqueToken('vh');
        await input.store.putGrant({
          hash: tokenHash(handle),
          subject,
          kind: 'view',
          expiresAtMs: expiresAt(),
        });
        return {
          ok: true as const,
          handle,
          counts: {
            dexa: snapshot.dexa.length,
            photos: snapshot.photos.length,
            weigh_ins: snapshot.weighIns.length,
          },
        };
      } catch {
        return { ok: false as const };
      }
    },

    async redeem(handle, apiOrigin) {
      const grant = await input.store.takeGrant(tokenHash(handle), 'view', input.now());
      if (!grant) return { ok: false as const };
      try {
        const snapshot = await input.reader.read(grant.subject);
        const confirmToken = newOpaqueToken('ct');
        await input.store.putGrant({
          hash: tokenHash(confirmToken),
          subject: grant.subject,
          kind: 'confirm',
          expiresAtMs: expiresAt(),
        });
        const photos = [];
        for (const photo of snapshot.photos) {
          let imageUrl: string | null = null;
          try {
            imageUrl = await mediaUrl(photo, grant.subject, apiOrigin);
          } catch {
            imageUrl = null;
          }
          photos.push({ id: photo.id, imageUrl });
        }
        return {
          ok: true as const,
          view: {
            confirmToken,
            dexa: snapshot.dexa.map((row) => ({
              id: row.id,
              measuredOn: row.measuredOn,
              bodyFatPercent: row.bodyFatPercent,
              leanMassKg: row.leanMassKg,
            })),
            photos,
            weighIns: snapshot.weighIns.map((row) => ({
              id: row.id,
              measuredOn: row.measuredOn,
              weightKg: row.weightKg,
            })),
          },
        };
      } catch {
        return { ok: false as const };
      }
    },

    async confirm({ confirmToken, fields }) {
      const unique = HEALTH_VAULT_SHARE_FIELDS.filter((field) => fields.includes(field));
      if (!unique.length) return { ok: false as const };
      const grant = await input.store.takeGrant(tokenHash(confirmToken), 'confirm', input.now());
      if (!grant) return { ok: false as const };
      const consentId = newOpaqueToken('co');
      await input.store.putGrant({
        hash: tokenHash(consentId),
        subject: grant.subject,
        kind: 'consent',
        expiresAtMs: expiresAt(),
        fields: unique,
      });
      return { ok: true as const, consentId };
    },

    async share(subject, consentId) {
      const grant = await input.store.takeGrant(tokenHash(consentId), 'consent', input.now());
      if (!grant || !grant.fields?.length) return { ok: false as const };
      if (grant.subject !== subject) {
        await input.store.putGrant(grant);
        return { ok: false as const };
      }
      try {
        const snapshot = await input.reader.read(subject);
        const fields = grant.fields satisfies ShareField[];
        const summary = summarizeVault(snapshot, fields);
        await input.store.appendConsent({
          subject,
          consentId,
          fields,
          at: input.now().toISOString(),
        });
        return { ok: true as const, fields, summary };
      } catch {
        return { ok: false as const };
      }
    },
  };
}
