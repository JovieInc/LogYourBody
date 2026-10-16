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
    access: () => 'ok',
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
    const { handlers, provider } = createHandlers({ access: () => 'disabled' });
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/speak', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({ text: 'A short spoken response.' }),
    });

    expect((await handlers.speak(request)).status).toBe(404);
    expect(provider.tts).not.toHaveBeenCalled();
  });

  it('rejects a non-allowlisted caller before speech or intent work', async () => {
    const reserveRequest = jest.fn(async () => ({
      allowed: true,
      remainingInWindow: 11,
      remainingToday: 99,
    }));
    const { handlers, provider } = createHandlers({
      access: () => 'forbidden',
      reserveRequest,
    });
    const headers = { authorization: 'Bearer test-token', 'content-type': 'application/json' };

    const speak = await handlers.speak(
      new NextRequest('http://localhost/api/auth/mobile/voice/v1/speak', {
        method: 'POST',
        headers,
        body: JSON.stringify({ text: 'A short spoken response.' }),
      }),
    );
    const intent = await handlers.intent(
      new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
        method: 'POST',
        headers,
        body: JSON.stringify({ transcript: 'Log 8 reps at 185' }),
      }),
    );

    expect(speak.status).toBe(403);
    await expect(speak.json()).resolves.toEqual({ version: 1, error: 'forbidden' });
    expect(intent.status).toBe(403);
    expect(provider.tts).not.toHaveBeenCalled();
    expect(reserveRequest).not.toHaveBeenCalled();
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

  it('returns a plan edit proposal and does not apply it', async () => {
    const { handlers } = createHandlers();
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({
        transcript: 'Swap incline dumbbell press for the Smith machine incline press',
      }),
    });

    const response = await handlers.intent(request);
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      version: 1,
      kind: 'plan_edit',
      requiresConfirmation: true,
      applied: false,
      operation: {
        kind: 'swap',
        exerciseName: 'incline dumbbell press',
        toVariantId: 'smith_incline_press',
        declareEquipment: ['smith'],
      },
    });
  });

  it('binds terse in-session speech to the supplied canonical current set', async () => {
    const { handlers } = createHandlers();
    const response = await handlers.intent(
      new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
        method: 'POST',
        headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
        body: JSON.stringify({
          transcript: 'nine reps, probably one left',
          weightUnit: 'kg',
          session: {
            id: '11111111-1111-4111-8111-111111111111',
            exercises: [{ id: 'bench_press', name: 'Bench Press' }],
            currentSet: {
              exerciseId: 'bench_press',
              exerciseName: 'Bench Press',
              setNumber: 2,
              reps: 10,
              loadKg: 80,
              rir: 2,
            },
          },
        }),
      }),
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      kind: 'log_set',
      proposal: {
        exerciseId: 'bench_press',
        setNumber: 2,
        reps: 9,
        loadKg: 80,
        rir: 1,
      },
    });
  });

  it('leaves an ordinary message as a message', async () => {
    const { handlers } = createHandlers();
    const request = new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
      method: 'POST',
      headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
      body: JSON.stringify({ transcript: 'How is my week looking?' }),
    });

    await expect((await handlers.intent(request)).json()).resolves.toEqual({
      version: 1,
      kind: 'message',
    });
  });

  it('routes correction and interruption phrases without mutating state', async () => {
    const { handlers } = createHandlers();
    const session = {
      id: '11111111-1111-4111-8111-111111111111',
      exercises: [{ id: 'incline_press', name: 'Incline press' }],
      currentSet: {
        exerciseId: 'incline_press',
        exerciseName: 'Incline press',
        setNumber: 2,
        reps: 10,
        loadKg: 30,
        rir: 2,
      },
      lastCompletedSet: {
        exerciseId: 'incline_press',
        exerciseName: 'Incline press',
        setNumber: 1,
        reps: 10,
        loadKg: 30,
        rir: 2,
      },
    };
    const intent = async (transcript: string) =>
      (
        await handlers.intent(
          new NextRequest('http://localhost/api/auth/mobile/voice/v1/intent', {
            method: 'POST',
            headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
            body: JSON.stringify({ transcript, weightUnit: 'kg', session }),
          }),
        )
      ).json();

    await expect(intent('actually nine, not ten')).resolves.toMatchObject({
      kind: 'correct_set',
      proposal: { setNumber: 1, reps: 9, loadKg: 30, rir: 2 },
    });
    await expect(intent('bench is taken')).resolves.toMatchObject({
      kind: 'workout_action',
      action: { kind: 'equipment_unavailable', exerciseId: 'incline_press' },
    });
    await expect(intent('I only have 30 minutes')).resolves.toMatchObject({
      kind: 'workout_action',
      action: { kind: 'shorten', minutes: 30 },
    });
    await expect(intent('skip this today')).resolves.toMatchObject({
      kind: 'workout_action',
      action: { kind: 'skip', exerciseId: 'incline_press' },
    });
    await expect(intent('my shoulder hurts on this')).resolves.toMatchObject({
      kind: 'workout_action',
      requiresConfirmation: false,
      action: { kind: 'pain', exerciseId: 'incline_press' },
    });
  });
});
