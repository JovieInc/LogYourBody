/**
 * Server-side provider retention switches.
 *
 * OpenAI Chat Completions `store: false` is set on every direct call. It turns
 * off application-state storage and does not change the completion. Full OpenAI
 * Zero Data Retention (the abuse-monitoring exemption) cannot be set from the SDK.
 *
 * ElevenLabs `enableLogging: false` and AI Gateway `zeroDataRetention: true`
 * can fail the request when the account or model is not eligible, so they stay
 * behind `LYB_AI_ZERO_RETENTION=1`.
 */
export const AI_ZERO_RETENTION_ENV = 'LYB_AI_ZERO_RETENTION';

export function isAiZeroRetentionEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env[AI_ZERO_RETENTION_ENV] === '1';
}

export function elevenLabsZeroRetentionProviderOptions(env: NodeJS.ProcessEnv = process.env) {
  if (!isAiZeroRetentionEnabled(env)) return undefined;
  return { elevenlabs: { enableLogging: false } };
}

export function gatewayZeroRetentionProviderOptions(env: NodeJS.ProcessEnv = process.env) {
  if (!isAiZeroRetentionEnabled(env)) return undefined;
  return { gateway: { zeroDataRetention: true } };
}
