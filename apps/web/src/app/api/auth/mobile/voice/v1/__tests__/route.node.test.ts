/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createVoiceRouteHandlers } from '../route-handlers';
import type { VoiceProvider } from '@/lib/voice/provider';

function byteStream(values: number[]) {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(values));
      controller.close();
    },
  });
}

function createHandlers(overrides: Partial<Parameters<typeof createVoiceRouteHandlers>[0]> = {}) {
  const provider: VoiceProvider = {
    tts: jest.fn(async () => byteStream([1, 2, 3, 4])),
  };
  const dependencies: Parameters<typeof createVoiceRouteHandlers>[0] = {
    authenticate: jest.fn(async () => ({ sub: 'user-1' }) as never),
    enabled: () => true,
    provider: () => provider,
    voiceId: () => 'A4j35F5T4XsPMeXd06Pm',
    reserveRequest: jest.fn(async () => ({
      allowed: true,
      remainingInWindow: 11,
      remainingToday: 99,
    })),
    createRequestId: () => 'request-1',
    ...overrides,
  };
  return { handlers: createVoiceRouteHandlers(dependencies), provider };
}

describe('mobile voice routes', () => {
  it('streams generated speech without caching it', async () => {
    const { handlers, provider } = createHandlers();
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/speak', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({ text: 'A short spoken response.' }),
    });

    const response = await handlers.speak(request);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('audio/mpeg');
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3, 4]));
    expect(provider.tts).toHaveBeenCalledWith('A short spoken response.', 'A4j35F5T4XsPMeXd06Pm', {
      signal: request.signal,
    });
  });

  it('does not call a provider when voice is disabled', async () => {
    const { handlers, provider } = createHandlers({ enabled: () => false });
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/speak', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({ text: 'A short spoken response.' }),
    });

    expect((await handlers.speak(request)).status).toBe(404);
    expect(provider.tts).not.toHaveBeenCalled();
  });

  it('returns a confirmed-only set proposal and never writes a set', async () => {
    const { handlers } = createHandlers();
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({
        transcript: 'Log set 2 of bench press, 8 reps at 185 lbs, 2 RIR',
        weightUnit: 'kg',
        session: {
          id: '11111111-1111-4111-8111-111111111111',
          exercises: [{ id: 'bench_press', name: 'Bench Press' }],
        },
      }),
    });

    const response = await handlers.intent(request);
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      version: 1,
      kind: 'log_set',
      requiresConfirmation: true,
      missingFields: [],
      proposal: {
        sessionId: '11111111-1111-4111-8111-111111111111',
        exerciseId: 'bench_press',
        exerciseName: 'Bench Press',
        setNumber: 2,
        reps: 8,
        loadKg: 83.91,
        rir: 2,
      },
      heard: { setNumber: 2, reps: 8, loadValue: 185, weightUnit: 'lbs', loadKg: 83.91, rir: 2 },
    });
  });

  it('identifies missing context for a short set command instead of guessing', async () => {
    const { handlers } = createHandlers();
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({ transcript: 'Log 8 reps at 185, 2 RIR', weightUnit: 'lbs' }),
    });

    await expect((await handlers.intent(request)).json()).resolves.toMatchObject({
      kind: 'log_set',
      requiresConfirmation: true,
      missingFields: ['session', 'exercise', 'set_number'],
      proposal: null,
      heard: { reps: 8, loadValue: 185, weightUnit: 'lbs', loadKg: 83.91, rir: 2 },
    });
  });
});
