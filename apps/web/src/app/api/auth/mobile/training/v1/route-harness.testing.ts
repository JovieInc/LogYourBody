import { NextRequest } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { createTrainingRouteHandlers } from './route-handlers';

const tokens: Record<string, string> = { 'token-a': 'subject-a', 'token-b': 'subject-b' };

export function makeHarness(
  options: { enabled?: boolean; selectionEnabled?: boolean; rateLimited?: boolean } = {},
) {
  const records = new MemoryTrainingRecords();
  let currentTime = new Date('2026-01-10T12:00:00.000Z');
  let nextId = 1;
  const handlers = createTrainingRouteHandlers({
    authenticate: async (request) => {
      const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
      const subject = token ? tokens[token] : undefined;
      return subject ? ({ sub: subject } as JovieUserInfo) : null;
    },
    records,
    users: {
      getUser: async () => ({ profileData: { date_of_birth: '1990-01-01' } }) as never,
    } as never,
    reserveRequest: async () =>
      options.rateLimited
        ? { allowed: false, retryAfterSeconds: 30 }
        : { allowed: true, remainingInWindow: 9, remainingToday: 99 },
    createId: () => `11111111-1111-4111-8111-${String(nextId++).padStart(12, '0')}`,
    now: () => currentTime,
    enabled: () => options.enabled ?? true,
    selectionEnabled: () => options.selectionEnabled ?? true,
  });
  return {
    handlers,
    records,
    setNow: (value: string) => {
      currentTime = new Date(value);
    },
  };
}

export function request(method: string, path: string, token?: string, body?: unknown) {
  return new NextRequest(`http://localhost/api/auth/mobile/training/v1/${path}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

export const eligibleSetup = {
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
};
