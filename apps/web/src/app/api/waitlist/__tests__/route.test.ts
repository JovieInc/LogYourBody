/**
 * @jest-environment node
 */

import { NextRequest } from 'next/server';
import { POST } from '../route';
import { upsertWaitlistEntry } from '@/lib/waitlist/store';

jest.mock('@/lib/waitlist/store', () => ({
  upsertWaitlistEntry: jest.fn(),
}));

const mockedUpsert = upsertWaitlistEntry as jest.MockedFunction<typeof upsertWaitlistEntry>;

function makeRequest(body: unknown) {
  return new NextRequest('http://localhost/api/waitlist', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /api/waitlist', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('creates a waitlist entry and returns 201', async () => {
    mockedUpsert.mockResolvedValueOnce({ status: 'created', id: 'entry-1' });

    const response = await POST(makeRequest({ email: 'new@example.com' }));
    const payload = await response.json();

    expect(response.status).toBe(201);
    expect(payload).toEqual({ success: true, status: 'created', id: 'entry-1' });
  });

  it('returns 200 for idempotent duplicate signups', async () => {
    mockedUpsert.mockResolvedValueOnce({ status: 'existing', id: 'entry-2' });

    const response = await POST(makeRequest({ email: 'existing@example.com' }));
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload).toEqual({ success: true, status: 'existing', id: 'entry-2' });
  });

  it('returns 400 for missing email', async () => {
    const response = await POST(makeRequest({ email: '   ' }));
    expect(response.status).toBe(400);
    expect(mockedUpsert).not.toHaveBeenCalled();
  });
});
