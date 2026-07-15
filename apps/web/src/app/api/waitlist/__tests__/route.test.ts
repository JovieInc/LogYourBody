/**
 * @jest-environment node
 */

import { NextRequest } from 'next/server';
import { POST } from '../route';
import { acceptWaitlistEntry } from '@/lib/waitlist/store';

jest.mock('@/lib/waitlist/store', () => ({
  acceptWaitlistEntry: jest.fn(),
}));

const mockedAccept = acceptWaitlistEntry as jest.MockedFunction<typeof acceptWaitlistEntry>;

function makeRequest(
  body: unknown,
  headers: Record<string, string> = { 'Content-Type': 'application/json' },
) {
  return new NextRequest('http://localhost/api/waitlist', {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

describe('POST /api/waitlist', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('accepts a waitlist entry without exposing its database id or membership state', async () => {
    mockedAccept.mockResolvedValueOnce();

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
  });

  it.each([
    [{ email: '   ' }, 400],
    [{ email: 'person@example.com', source: '<script>' }, 400],
    ['{not-json', 400],
  ])('rejects invalid input', async (body, status) => {
    const response = await POST(makeRequest(body));
    expect(response.status).toBe(status);
    expect(mockedAccept).not.toHaveBeenCalled();
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
