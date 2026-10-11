import type { VoiceProvider, VoiceProviderId } from '../provider';
import { createElevenLabsVoiceProvider } from './elevenlabs';
import { createFishAudioVoiceProvider } from './fish-audio';

export type VoiceProviderEnvironment = {
  elevenLabsApiKey?: string;
  aiGatewayApiKey?: string;
  fetch?: typeof fetch;
};

export function createVoiceProviders(environment: VoiceProviderEnvironment = {}) {
  const shared = { fetch: environment.fetch };
  return {
    elevenlabs: createElevenLabsVoiceProvider({
      ...shared,
      apiKey: environment.elevenLabsApiKey,
    }),
    'fish-audio': createFishAudioVoiceProvider({
      ...shared,
      apiKey: environment.aiGatewayApiKey,
    }),
  } satisfies Record<VoiceProviderId, VoiceProvider>;
}

export function getVoiceProviderId(value: string | undefined): VoiceProviderId | null {
  if (value === 'elevenlabs' || value === 'fish-audio') return value;
  return null;
}
