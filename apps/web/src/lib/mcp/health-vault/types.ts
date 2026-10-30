/** Privacy boundary for LYB-330.
 * MCP `open` returns a handle and counts. Measurements leave the server only
 * through `redeem` (browser ↔ LogYourBody) or `share` after the widget confirms.
 */

export const HEALTH_VAULT_SHARE_FIELDS = ['lean_mass', 'body_fat', 'weight'] as const;
export type ShareField = (typeof HEALTH_VAULT_SHARE_FIELDS)[number];

export type VaultCounts = {
  dexa: number;
  photos: number;
  weigh_ins: number;
};

export type VaultDexa = {
  id: string;
  measuredOn: string;
  bodyFatPercent: number;
  leanMassKg: number | null;
};

export type VaultPhoto = {
  id: string;
  imageUrl?: string | null;
  bytes?: Uint8Array;
  contentType?: string;
};

export type VaultWeighIn = {
  id: string;
  measuredOn: string;
  weightKg: number;
};

export type VaultSnapshot = {
  dexa: VaultDexa[];
  photos: VaultPhoto[];
  weighIns: VaultWeighIn[];
};

export type VaultSeries = {
  first: number;
  last: number;
  delta: number;
  samples: number;
};

export type VaultSummary = {
  lean_mass?: VaultSeries;
  body_fat?: VaultSeries;
  weight?: VaultSeries;
};

export type VaultViewPhoto = {
  id: string;
  imageUrl: string | null;
};

export type VaultView = {
  confirmToken: string;
  dexa: VaultDexa[];
  photos: VaultViewPhoto[];
  weighIns: VaultWeighIn[];
};

export type VaultOpenResult = { ok: true; handle: string; counts: VaultCounts } | { ok: false };

export type VaultRedeemResult = { ok: true; view: VaultView } | { ok: false };

export type VaultConfirmResult = { ok: true; consentId: string } | { ok: false };

export type VaultShareResult =
  { ok: true; fields: ShareField[]; summary: VaultSummary } | { ok: false };

export interface HealthVaultReader {
  read(subject: string): Promise<VaultSnapshot>;
}

export interface HealthVaultService {
  open(subject: string): Promise<VaultOpenResult>;
  redeem(handle: string, apiOrigin: string): Promise<VaultRedeemResult>;
  confirm(input: { confirmToken: string; fields: ShareField[] }): Promise<VaultConfirmResult>;
  share(subject: string, consentId: string): Promise<VaultShareResult>;
}
