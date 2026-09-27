import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createElevenLabsVoiceProvider } from '../src/lib/voice/providers/elevenlabs';
import { createFishAudioVoiceProvider } from '../src/lib/voice/providers/fish-audio';

async function readStream(stream: ReadableStream<Uint8Array>) {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  for (;;) {
    const result = await reader.read();
    if (result.done) break;
    chunks.push(result.value);
  }
  return Uint8Array.from(chunks.flatMap((chunk) => Array.from(chunk)));
}

test('ElevenLabs SDK transport generates speech and transcribes audio', async () => {
  const requests: Array<{ url: string; headers: Headers; method: string }> = [];
  const mockFetch: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    requests.push({ url: request.url, headers: request.headers, method: request.method });
    if (request.url.includes('speech-to-text')) {
      return Response.json({
        language_code: 'eng',
        language_probability: 0.99,
        text: 'Log set 1 of bench press, 8 reps at 185 lbs, 2 RIR',
      });
    }
    return new Response(new Uint8Array([10, 20, 30]), {
      status: 200,
      headers: { 'content-type': 'audio/mpeg' },
    });
  };
  const provider = createElevenLabsVoiceProvider({
    apiKey: 'test-elevenlabs-key',
    fetch: mockFetch,
  });

  const audio = await provider.tts('A measured response.', 'test-voice');
  assert.deepEqual(await readStream(audio), new Uint8Array([10, 20, 30]));
  assert.equal(
    await provider.stt!(new Uint8Array([1, 2, 3])),
    'Log set 1 of bench press, 8 reps at 185 lbs, 2 RIR',
  );

  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /\/text-to-speech\/test-voice/);
  assert.equal(requests[0].headers.get('xi-api-key'), 'test-elevenlabs-key');
  assert.match(requests[1].url, /\/speech-to-text/);
  assert.equal(requests[1].headers.get('xi-api-key'), 'test-elevenlabs-key');
});

test('Fish Audio uses the AI Gateway speech model transport', async () => {
  const requests: Array<{ url: string; headers: Headers; body: Record<string, unknown> }> = [];
  const mockFetch: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    requests.push({ url: request.url, headers: request.headers, body: await request.json() });
    return Response.json({ audio: Buffer.from([4, 5, 6]).toString('base64') });
  };
  const provider = createFishAudioVoiceProvider({ apiKey: 'test-gateway-key', fetch: mockFetch });

  const audio = await provider.tts('A measured response.', 'test-voice');
  assert.deepEqual(await readStream(audio), new Uint8Array([4, 5, 6]));
  assert.equal(requests.length, 1);
  assert.match(requests[0].url, /\/speech-model/);
  assert.equal(requests[0].headers.get('authorization'), 'Bearer test-gateway-key');
  assert.equal(requests[0].headers.get('ai-model-id'), 'fish-audio/s2.1-pro');
  assert.deepEqual(requests[0].body, {
    text: 'A measured response.',
    voice: 'test-voice',
    outputFormat: 'mp3',
    providerOptions: {},
  });
});
