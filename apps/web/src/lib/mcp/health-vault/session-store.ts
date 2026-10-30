import { createHash, randomBytes } from 'node:crypto';
import type { ShareField } from './types';

export type GrantKind = 'view' | 'confirm' | 'consent' | 'media';

export type StoredGrant = {
  hash: string;
  subject: string;
  kind: GrantKind;
  expiresAtMs: number;
  fields?: ShareField[];
};

export type StoredMedia = {
  hash: string;
  subject: string;
  expiresAtMs: number;
  contentType: string;
  bytes: Uint8Array;
};

export type ConsentEvent = {
  subject: string;
  consentId: string;
  fields: ShareField[];
  at: string;
};

export interface HealthVaultSessionStore {
  putGrant(grant: StoredGrant): Promise<void>;
  /** Removes the grant. Expired and kind-mismatched tokens return null. */
  takeGrant(hash: string, kind: GrantKind, now: Date): Promise<StoredGrant | null>;
  putMedia(media: StoredMedia): Promise<void>;
  readMedia(hash: string, now: Date): Promise<StoredMedia | null>;
  appendConsent(event: ConsentEvent): Promise<void>;
}

export function newOpaqueToken(prefix: string): string {
  return `${prefix}_${randomBytes(32).toString('base64url')}`;
}

export function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export class MemoryHealthVaultStore implements HealthVaultSessionStore {
  readonly grants = new Map<string, StoredGrant>();
  readonly media = new Map<string, StoredMedia>();
  readonly events: ConsentEvent[] = [];

  async putGrant(grant: StoredGrant): Promise<void> {
    this.grants.set(grant.hash, grant);
  }

  async takeGrant(hash: string, kind: GrantKind, now: Date): Promise<StoredGrant | null> {
    const grant = this.grants.get(hash);
    if (!grant || grant.kind !== kind) return null;
    this.grants.delete(hash);
    if (grant.expiresAtMs <= now.getTime()) return null;
    return grant;
  }

  async putMedia(media: StoredMedia): Promise<void> {
    this.media.set(media.hash, media);
  }

  async readMedia(hash: string, now: Date): Promise<StoredMedia | null> {
    const media = this.media.get(hash);
    if (!media) return null;
    if (media.expiresAtMs <= now.getTime()) {
      this.media.delete(hash);
      return null;
    }
    return media;
  }

  async appendConsent(event: ConsentEvent): Promise<void> {
    this.events.push(event);
  }
}
