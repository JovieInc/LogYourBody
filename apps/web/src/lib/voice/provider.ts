export type VoiceProviderOptions = {
  signal?: AbortSignal;
  modelId?: string;
};

export interface VoiceProvider {
  tts(
    text: string,
    voiceId: string,
    options?: VoiceProviderOptions,
  ): Promise<ReadableStream<Uint8Array>>;
  stt?(audio: Uint8Array, options?: VoiceProviderOptions): Promise<string>;
}

export type VoiceProviderId = 'elevenlabs' | 'fish-audio';

export function audioBytesStream(audio: Uint8Array): ReadableStream<Uint8Array> {
  const bytes = audio.slice();
  return new ReadableStream({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}
