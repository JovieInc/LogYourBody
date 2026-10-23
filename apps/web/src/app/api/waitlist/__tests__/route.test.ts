/**
 * @jest-environment node
 */

import { NextRequest } from 'next/server';
import { POST } from '../route';
import { acceptWaitlistEntry } from '@/lib/waitlist/store';

const mockQuery = jest.fn();
jest.mock('@neondatabase/serverless', () => ({ neon: jest.fn(() => mockQuery) }));

jest.mock('@/lib/waitlist/store', () => ({
  acceptWaitlistEntry: jest.fn(),
}));

const mockedAccept = acceptWaitlistEntry as jest.MockedFunction<typeof acceptWaitlistEntry>;

function makeRequest(
  body: unknown,
  headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'x-vercel-forwarded-for': '192.0.2.1',
  },
) {
  return new NextRequest('http://localhost/api/waitlist', {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

describe('POST /api/waitlist', () => {
  let rejected: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.DATABASE_URL = 'postgresql://example.test/product';
    process.env.VERCEL = '1';
    mockQuery.mockReset().mockResolvedValue([{ allowed: true, retry_after: 600 }]);
    rejected = jest.spyOn(console, 'info').mockImplementation(() => {});
  });

  afterEach(() => rejected.mockRestore());

  it('accepts a waitlist entry without exposing its database id or membership state', async () => {
    mockedAccept.mockResolvedValueOnce({ created: true });

    const response = await POST(
      makeRequest({ email: 'new@example.com', source: 'landing:minimal:direct' }),
    );

    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ success: true });
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(mockedAccept).toHaveBeenCalledWith({
      email: 'new@example.com',
      source: 'landing:minimal:direct',
    });
  });

  it('silently accepts honeypot submissions without writing', async () => {
    const response = await POST(
      makeRequest({ email: 'bot@example.com', website: 'https://spam.example' }),
    );

    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ success: true });
    expect(mockedAccept).not.toHaveBeenCalled();
    expect(rejected).toHaveBeenCalledWith('[api/waitlist] rejected', {
      count: 1,
      status: 202,
      reason: 'honeypot',
    });
  });

  it('limits repeated attempts from one IP before inserting another email', async () => {
    // The database counter admits five reservations, then rejects the sixth.
    mockQuery.mockReset();
    for (let attempt = 0; attempt < 5; attempt++) {
      mockQuery.mockResolvedValueOnce([{ allowed: true, retry_after: 600 }]);
    }
    mockQuery.mockResolvedValueOnce([{ allowed: false, retry_after: 600 }]);
    for (let attempt = 0; attempt < 5; attempt++) {
      expect((await POST(makeRequest({ email: `person${attempt}@example.com` }))).status).toBe(202);
    }

    const response = await POST(makeRequest({ email: 'limited@example.com' }));
    expect(response.status).toBe(429);
    expect(await response.json()).toEqual({
      success: false,
      error: 'Something went wrong. Please try again.',
    });
    expect(response.headers.get('Retry-After')).toBe('600');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(mockedAccept).toHaveBeenCalledTimes(5);
    expect(mockQuery).toHaveBeenCalledTimes(6);
    expect(rejected.mock.calls).toEqual([['[api/waitlist] rejected', { count: 1, status: 429 }]]);
  });

  it('limits before reading the body, including invalid and honeypot submissions', async () => {
    mockQuery.mockResolvedValue([{ allowed: false, retry_after: 37 }]);
    const request = makeRequest({ email: 'private@example.com', website: 'spam' });
    const read = jest.spyOn(request, 'text');
    expect((await POST(request)).headers.get('Retry-After')).toBe('37');
    expect(read).not.toHaveBeenCalled();
    expect(mockedAccept).not.toHaveBeenCalled();
    expect(JSON.stringify(rejected.mock.calls)).not.toContain('private@example.com');
  });

  it('fails closed without leaking details when the rate-limit store is unavailable', async () => {
    const log = jest.spyOn(console, 'error').mockImplementation(() => {});
    mockQuery.mockRejectedValueOnce(new Error('postgresql://secret private@example.com'));
    try {
      const response = await POST(makeRequest({ email: 'private@example.com' }));
      expect(response.status).toBe(500);
      expect(mockedAccept).not.toHaveBeenCalled();
      expect(rejected).toHaveBeenCalledWith('[api/waitlist] rejected', { count: 1, status: 500 });
      expect(JSON.stringify([log.mock.calls, rejected.mock.calls])).not.toMatch(
        /secret|private@example/,
      );
    } finally {
      log.mockRestore();
    }
  });

  it('accepts the production smoke honeypot without an email or database write', async () => {
    const response = await POST(makeRequest({ website: 'production-smoke' }));

    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ success: true });
    expect(mockedAccept).not.toHaveBeenCalled();
  });

  it('returns the same public response for a duplicate or suppressed registration', async () => {
    mockedAccept.mockResolvedValueOnce({ created: false });
    const response = await POST(makeRequest({ email: 'existing@example.com' }));
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ success: true });
  });

  it('accepts schema-length sources and rejects longer ones before writing', async () => {
    mockedAccept.mockResolvedValueOnce({ created: true });
    expect(
      (await POST(makeRequest({ email: 'synthetic@example.com', source: 'a'.repeat(64) }))).status,
    ).toBe(202);
    jest.clearAllMocks();
    expect(
      (await POST(makeRequest({ email: 'synthetic@example.com', source: 'a'.repeat(65) }))).status,
    ).toBe(400);
    expect(mockedAccept).not.toHaveBeenCalled();
  });

  it('does not log a database error containing contact data or credentials', async () => {
    const log = jest.spyOn(console, 'error').mockImplementation(() => {});
    mockedAccept.mockRejectedValueOnce(new Error('synthetic@example.com postgresql://secret'));
    try {
      const response = await POST(makeRequest({ email: 'synthetic@example.com' }));
      expect(response.status).toBe(500);
      expect(log).toHaveBeenCalledWith('[api/waitlist] Failed to persist waitlist entry');
      expect(JSON.stringify(log.mock.calls)).not.toMatch(/synthetic@example|secret/);
    } finally {
      log.mockRestore();
    }
  });

  it.each([
    [{ email: '   ' }, 400],
    [{ email: 'person@example.com', source: '<script>' }, 400],
    ['{not-json', 400],
  ])('rejects invalid input', async (body, status) => {
    const response = await POST(makeRequest(body));
    expect(response.status).toBe(status);
    expect(mockedAccept).not.toHaveBeenCalled();
    expect(rejected).toHaveBeenCalledWith('[api/waitlist] rejected', { count: 1, status });
  });

  it('requires JSON requests', async () => {
    const response = await POST(
      makeRequest('email=test@example.com', { 'Content-Type': 'text/plain' }),
    );
    expect(response.status).toBe(415);
  });

  it('rejects oversized bodies', async () => {
    const response = await POST(makeRequest({ email: `${'a'.repeat(5_000)}@example.com` }));
    expect(response.status).toBe(413);
  });

  it('maps invalid normalized emails to a generic validation response', async () => {
    mockedAccept.mockRejectedValueOnce(new Error('INVALID_EMAIL'));
    const response = await POST(makeRequest({ email: 'not-an-email' }));
    expect(response.status).toBe(400);
  });
});
