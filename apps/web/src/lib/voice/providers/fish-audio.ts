import { experimental_generateSpeech } from 'ai';
import { createGateway } from '@ai-sdk/gateway';
import { gatewayZeroRetentionProviderOptions } from '../../ai/zero-retention';
import { audioBytesStream, type VoiceProvider } from '../provider';

type FishAudioOptions = {
  apiKey?: string;
  fetch?: typeof fetch;
};

export function createFishAudioVoiceProvider(options: FishAudioOptions = {}): VoiceProvider {
  const gateway = createGateway(options);

  return {
    async tts(text, voiceId, requestOptions) {
      const retention = gatewayZeroRetentionProviderOptions();
      const result = await experimental_generateSpeech({
        model: gateway.speechModel(requestOptions?.modelId ?? 'fish-audio/s2.1-pro'),
        text,
        voice: voiceId,
        outputFormat: 'mp3',
        abortSignal: requestOptions?.signal,
        ...(retention ? { providerOptions: retention } : {}),
      });
      return audioBytesStream(result.audio.uint8Array);
    },
  };
}
