/** @jest-environment node */
import { createHmac, createHash } from 'node:crypto';
import { POST as inbound } from '@/app/api/customer-voice/inbound/route';
import { POST as reply } from '@/app/api/internal/customer-voice/[id]/reply/route';
import { neonCustomerVoice } from '@/lib/neon/customer-voice-adapter';
import {
  verifySummerOidcRequest,
  createSummerVoiceHandoff,
} from '@/lib/adapters/customer-voice-summer.server';

jest.mock('server-only', () => ({}));
jest.mock('@/lib/neon/customer-voice-adapter', () => ({
  neonCustomerVoice: {
    insert: jest.fn(async (item) => item),
    get: jest.fn(),
    stage: jest.fn(),
    claimReply: jest.fn(),
  },
}));
jest.mock('@/lib/adapters/customer-voice-summer.server', () => ({
  createSummerVoiceHandoff: jest.fn(() => ({ forward: jest.fn(async () => ({})) })),
  verifySummerOidcRequest: jest.fn(),
}));
jest.mock('@/lib/adapters/StatsigPublicLandingAdapter.server', () => ({
  readPublicLandingGate: jest.fn(),
}));

it('wires signed email to durable capture and Summer with live server-only config', async () => {
  const previous = {
    salt: process.env.CUSTOMER_VOICE_SALT,
    secret: process.env.CUSTOMER_VOICE_INBOUND_SECRET,
  };
  process.env.CUSTOMER_VOICE_SALT = 'fixture-salt';
  process.env.CUSTOMER_VOICE_INBOUND_SECRET = 'fixture-secret';
  try {
    const body = JSON.stringify({
      id: '11111111-2222-4333-8444-555555555555',
      receivedAt: '2026-10-31T00:00:00.000Z',
      from: 'browse-ready+route@jov.ie',
      text: 'bug report',
    });
    const response = await inbound(
      new Request('https://example.com/api/customer-voice/inbound', {
        method: 'POST',
        body,
        headers: {
          'x-customer-voice-signature': `sha256=${createHmac('sha256', 'fixture-secret').update(body).digest('hex')}`,
        },
      }),
    );
    expect(response.status).toBe(202);
    expect(neonCustomerVoice.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        event: expect.objectContaining({ app: 'logyourbody', test: true }),
      }),
    );
    expect(createSummerVoiceHandoff).toHaveBeenCalledTimes(1);
  } finally {
    if (previous.salt === undefined) delete process.env.CUSTOMER_VOICE_SALT;
    else process.env.CUSTOMER_VOICE_SALT = previous.salt;
    if (previous.secret === undefined) delete process.env.CUSTOMER_VOICE_INBOUND_SECRET;
    else process.env.CUSTOMER_VOICE_INBOUND_SECRET = previous.secret;
  }
});
it('wires Summer auth and returns an honest no-transport result from the actual reply route', async () => {
  const id = '11111111-2222-4333-8444-555555555555';
  const context = { params: Promise.resolve({ id }) };
  jest.mocked(verifySummerOidcRequest).mockResolvedValueOnce(false);
  expect(
    (await reply(new Request('https://example.com', { method: 'POST' }), context)).status,
  ).toBe(401);
  jest.mocked(verifySummerOidcRequest).mockResolvedValueOnce(true);
  jest.mocked(neonCustomerVoice.get).mockResolvedValueOnce({
    event: { replyable: true },
    replyTo: 'original@example.org',
    stages: {},
  } as never);
  const text = 'Thanks for your note. Tim';
  const response = await reply(
    new Request('https://example.com', {
      method: 'POST',
      body: JSON.stringify({
        text,
        draftSha256: createHash('sha256').update(text).digest('hex'),
        approvedAt: '2026-10-31T00:00:00.000Z',
        approvalKey: 'photon-fixture',
      }),
    }),
    context,
  );
  expect(response.status).toBe(501);
  expect(await response.json()).toEqual({ code: 'no-email-transport' });
  expect(neonCustomerVoice.claimReply).not.toHaveBeenCalled();
});
