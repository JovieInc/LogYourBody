/** @jest-environment node */
import { createHmac } from 'node:crypto';
import { reserveWaitlistRequest } from '../rate-limit';

const mockQuery = jest.fn();
jest.mock('@neondatabase/serverless', () => ({ neon: jest.fn(() => mockQuery) }));
jest.mock('server-only', () => ({}));

const databaseUrl = 'postgresql://example.test/product';
const originalVercel = process.env.VERCEL;
const originalDatabaseUrl = process.env.DATABASE_URL;

describe('shared waitlist rate limiter', () => {
  beforeEach(() => {
    process.env.VERCEL = '1';
    process.env.DATABASE_URL = databaseUrl;
    mockQuery.mockReset().mockResolvedValue([{ allowed: true, retry_after: 600 }]);
  });

  afterAll(() => {
    if (originalVercel === undefined) delete process.env.VERCEL;
    else process.env.VERCEL = originalVercel;
    if (originalDatabaseUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = originalDatabaseUrl;
  });

  it('reserves atomically with a stable private key and the five-attempt, ten-minute policy', async () => {
    await expect(
      reserveWaitlistRequest(new Headers({ 'x-vercel-forwarded-for': '192.0.2.1' })),
    ).resolves.toEqual({ allowed: true, retryAfterSeconds: 600 });
    const key = createHmac('sha256', databaseUrl).update('waitlist:v1:192.0.2.1').digest('hex');
    const [strings, ...values] = mockQuery.mock.calls[0];
    expect(values).toEqual([key, key, 600, 6, 5]);
    const statement = strings.join('?').replace(/\s+/g, ' ');
    expect(statement).toContain('on conflict (client_key) do update set');
    expect(statement).toContain('when limits.expires_at <= now() then 1');
    expect(statement).toContain('else least(limits.attempts + 1, ?) end');
    expect(statement).toContain('returning attempts <= ? as allowed');
    expect(statement).toContain(
      "expires_at < now() - interval '1 day' and client_key <> ? limit 100",
    );
    expect(JSON.stringify(values)).not.toMatch(/192\.0\.2\.1|postgresql/);
  });

  it('uses separate buckets for different IPs, ignoring spoofed forwarding headers on Vercel', async () => {
    for (const [trustedIp, spoofedIp] of [
      ['192.0.2.1', '198.51.100.1'],
      ['192.0.2.1', '198.51.100.2'],
      ['192.0.2.2', '198.51.100.1'],
    ]) {
      await reserveWaitlistRequest(
        new Headers({
          'x-vercel-forwarded-for': trustedIp,
          'x-forwarded-for': spoofedIp,
          'x-real-ip': spoofedIp,
        }),
      );
    }
    const keys = mockQuery.mock.calls.map((call) => call[1]);
    expect(keys[0]).toBe(keys[1]);
    expect(keys[0]).not.toBe(keys[2]);
  });

  it('normalizes equivalent IPv6 addresses into one bucket', async () => {
    await reserveWaitlistRequest(new Headers({ 'x-vercel-forwarded-for': '2001:db8::1' }));
    await reserveWaitlistRequest(
      new Headers({ 'x-vercel-forwarded-for': '2001:0db8:0:0:0:0:0:1' }),
    );
    expect(mockQuery.mock.calls[0][1]).toBe(mockQuery.mock.calls[1][1]);
  });

  it('shares a restrictive bucket for missing, malformed or multi-IP trusted headers', async () => {
    for (const headers of [
      { 'x-forwarded-for': '192.0.2.1' },
      { 'x-vercel-forwarded-for': 'invalid' },
      { 'x-vercel-forwarded-for': 'fe80::1%eth0' },
      { 'x-vercel-forwarded-for': '192.0.2.1, 192.0.2.2' },
    ]) {
      await reserveWaitlistRequest(new Headers(headers));
    }
    expect(new Set(mockQuery.mock.calls.map((call) => call[1])).size).toBe(1);
  });

  it('supports a sanitized forwarding header on non-Vercel hosts', async () => {
    delete process.env.VERCEL;
    await reserveWaitlistRequest(new Headers({ 'x-forwarded-for': '192.0.2.1' }));
    process.env.VERCEL = '1';
    await reserveWaitlistRequest(new Headers({ 'x-vercel-forwarded-for': '192.0.2.1' }));
    expect(mockQuery.mock.calls[0][1]).toBe(mockQuery.mock.calls[1][1]);
  });

  it('preserves the database denial and remaining retry time', async () => {
    mockQuery.mockResolvedValueOnce([{ allowed: false, retry_after: 37 }]);
    await expect(reserveWaitlistRequest(new Headers())).resolves.toEqual({
      allowed: false,
      retryAfterSeconds: 37,
    });
  });

  it.each([
    { rows: [] },
    { rows: [{ allowed: true, retry_after: 0 }] },
    { rows: [{ allowed: 'true', retry_after: 600 }] },
  ])('fails closed on an invalid database receipt (%j)', async ({ rows }) => {
    mockQuery.mockResolvedValueOnce(rows);
    await expect(reserveWaitlistRequest(new Headers())).rejects.toThrow(
      'Invalid waitlist rate limit receipt',
    );
  });

  it('requires the configured shared store instead of silently allowing requests', async () => {
    delete process.env.DATABASE_URL;
    await expect(reserveWaitlistRequest(new Headers())).rejects.toThrow('Missing DATABASE_URL');
    expect(mockQuery).not.toHaveBeenCalled();
  });
});
