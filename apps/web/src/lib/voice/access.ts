import type { VoiceProvider, VoiceProviderId } from './provider';

/**
 * Server policy for the default-off Statsig gate `hypertrophy_coach_voice_v1`.
 *
 * The gate (`LYB_VOICE_ENABLED`) is not enough. Voice also requires
 * `LYB_VOICE_ALLOWLIST`: comma-separated Jovie subject ids and/or emails.
 * That list defaults empty. No owner account id is stored in the repo, so
 * voice stays off for every account until the identifier is set outside git.
 */
export const HYPERTROPHY_COACH_VOICE_GATE = 'hypertrophy_coach_voice_v1';

export type VoiceAllowlistActor = {
  sub: string;
  email?: string | null;
};

export type VoiceCoachAccess = 'ok' | 'forbidden' | 'disabled';

type VoiceCoachEnv = {
  LYB_VOICE_ENABLED?: string;
  LYB_VOICE_ALLOWLIST?: string;
  [key: string]: string | undefined;
};

export function parseVoiceAllowlist(value: string | undefined | null): ReadonlySet<string> {
  if (!value) return new Set();
  const entries = value
    .split(/[,;\s]+/)
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .map((entry) => (entry.includes('@') ? entry.toLowerCase() : entry));
  return new Set(entries);
}

export function isVoiceAllowlisted(
  actor: VoiceAllowlistActor,
  allowlist: ReadonlySet<string>,
): boolean {
  if (allowlist.size === 0 || actor.sub.length === 0) return false;
  if (allowlist.has(actor.sub)) return true;
  const email = actor.email?.trim().toLowerCase();
  return Boolean(email && allowlist.has(email));
}

export function voiceCoachAccess(actor: VoiceAllowlistActor, env: VoiceCoachEnv): VoiceCoachAccess {
  if (!isVoiceAllowlisted(actor, parseVoiceAllowlist(env.LYB_VOICE_ALLOWLIST))) {
    return 'forbidden';
  }
  if (env.LYB_VOICE_ENABLED !== 'true') return 'disabled';
  return 'ok';
}

export function selectVoiceProvider(input: {
  providers: Record<VoiceProviderId, VoiceProvider>;
  providerId: VoiceProviderId | null;
  actor: VoiceAllowlistActor;
  allowlist: ReadonlySet<string>;
}): VoiceProvider | null {
  if (!isVoiceAllowlisted(input.actor, input.allowlist)) return null;
  if (input.providerId !== 'elevenlabs' && input.providerId !== 'fish-audio') return null;
  return input.providers[input.providerId];
}
