import { createElevenLabs } from '@ai-sdk/elevenlabs';
import { experimental_generateSpeech, experimental_transcribe } from 'ai';
import { audioBytesStream, type VoiceProvider } from '../provider';

type ElevenLabsOptions = {
  apiKey?: string;
  fetch?: typeof fetch;
};

export function createElevenLabsVoiceProvider(options: ElevenLabsOptions = {}): VoiceProvider {
  const elevenLabs = createElevenLabs(options);

  return {
    async tts(text, voiceId, requestOptions) {
      const result = await experimental_generateSpeech({
        model: elevenLabs.speech(requestOptions?.modelId ?? 'eleven_flash_v2_5'),
        text,
        voice: voiceId,
        outputFormat: 'mp3_44100_128',
        abortSignal: requestOptions?.signal,
      });
      return audioBytesStream(result.audio.uint8Array);
    },

    async stt(audio, requestOptions) {
      const result = await experimental_transcribe({
        model: elevenLabs.transcription(requestOptions?.modelId ?? 'scribe_v2'),
        audio,
        abortSignal: requestOptions?.signal,
        maxRetries: 0,
      });
      return result.text;
    },
  };
}
