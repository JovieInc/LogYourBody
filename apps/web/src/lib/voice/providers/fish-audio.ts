import { experimental_generateSpeech } from 'ai';
import { createGateway } from '@ai-sdk/gateway';
import { audioBytesStream, type VoiceProvider } from '../provider';

type FishAudioOptions = {
  apiKey?: string;
  fetch?: typeof fetch;
};

export function createFishAudioVoiceProvider(options: FishAudioOptions = {}): VoiceProvider {
  const gateway = createGateway(options);

  return {
    async tts(text, voiceId, requestOptions) {
      const result = await experimental_generateSpeech({
        model: gateway.speechModel(requestOptions?.modelId ?? 'fish-audio/s2.1-pro'),
        text,
        voice: voiceId,
        outputFormat: 'mp3',
        abortSignal: requestOptions?.signal,
      });
      return audioBytesStream(result.audio.uint8Array);
    },
  };
}
