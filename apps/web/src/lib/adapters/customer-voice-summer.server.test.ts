/** @jest-environment node */
import {
  createSummerVoiceHandoff,
  verifySummerOidcRequest,
  SUMMER_OIDC,
} from './customer-voice-summer.server';
import { jwtVerify, createRemoteJWKSet } from 'jose';
import { privateSupportSummary } from '@/lib/customer-voice/event';
jest.mock('server-only', () => ({}));
jest.mock('jose', () => ({ jwtVerify: jest.fn(), createRemoteJWKSet: jest.fn(() => jest.fn()) }));
const event = {
  schema: 'company.customer-voice/v1',
  app: 'logyourbody',
  id: '11111111-2222-4333-8444-555555555555',
  channel: 'email',
  receivedAt: '2026-10-31T00:00:00.000Z',
  ...privateSupportSummary('refund'),
  who: 'LogYourBody customer',
  replyable: true,
  urgent: true,
  test: false,
} as const;
const env = { SUMMER_BASE_URL: 'https://summer.example', VERCEL_OIDC_TOKEN: 'token-fixture' };

it.each([{}, { SUMMER_BASE_URL: env.SUMMER_BASE_URL }, { VERCEL_OIDC_TOKEN: 'fixture' }])(
  'fails closed without both credentials (%j)',
  async (missing) => {
    const fetcher = jest.fn();
    await expect(createSummerVoiceHandoff(missing, fetcher).forward(event)).rejects.toThrow(
      'handoff-unavailable',
    );
    expect(fetcher).not.toHaveBeenCalled();
  },
);
it.each([
  'http://summer.example',
  'https://user:pass@summer.example',
  'https://summer.example/path',
  'https://summer.example/?token=secret',
  'https://summer.example/#x',
])('rejects unsafe origins %s', async (origin) => {
  await expect(
    createSummerVoiceHandoff({ ...env, SUMMER_BASE_URL: origin }, jest.fn()).forward(event),
  ).rejects.toThrow();
});
it('sends exactly the strict event and OIDC headers with no redirects or retry', async () => {
  const fetcher = jest
    .fn()
    .mockResolvedValue(Response.json({ result: { status: 'pinged', pingedAt: event.receivedAt } }));
  const adapter = createSummerVoiceHandoff(env, fetcher);
  expect(await adapter.forward(event)).toEqual({ pingedAt: event.receivedAt });
  expect(fetcher.mock.calls[0][0].href).toBe(
    'https://summer.example/ovie/v1/customer-voice/events',
  );
  expect(fetcher.mock.calls[0][1]).toMatchObject({
    method: 'POST',
    redirect: 'error',
    cache: 'no-store',
    headers: {
      authorization: 'Bearer token-fixture',
      'x-vercel-trusted-oidc-idp-token': 'token-fixture',
      'content-type': 'application/json',
    },
  });
  expect(JSON.parse(fetcher.mock.calls[0][1].body)).toEqual(event);
  await expect(adapter.forward({ ...event, health: 'secret' } as typeof event)).rejects.toThrow();
  expect(fetcher).toHaveBeenCalledTimes(1);
});
it('accepts digest/replay receipts but rejects ambiguous success and failed/malformed responses', async () => {
  for (const status of ['digested', 'replay']) {
    const adapter = createSummerVoiceHandoff(
      env,
      jest.fn().mockResolvedValue(Response.json({ result: { status } })),
    );
    expect(await adapter.forward(event)).toEqual({});
  }
  for (const response of [
    Response.json({}),
    Response.json({ result: { status: 'unknown' } }),
    Response.json({ result: { status: 'pinged', pingedAt: 'bad' } }),
    Response.json({ result: { status: 'pinged' } }),
    Response.json({ result: { status: 'replay' } }, { status: 500 }),
    new Response('bad json'),
  ]) {
    await expect(
      createSummerVoiceHandoff(env, jest.fn().mockResolvedValue(response)).forward(event),
    ).rejects.toThrow();
  }
  await expect(
    createSummerVoiceHandoff(env, jest.fn().mockRejectedValue(new Error('timeout'))).forward(event),
  ).rejects.toThrow('timeout');
});
it('authenticates only Summer production identity and fails closed for JWKS failures', async () => {
  const valid = new Request('https://example.com', {
    headers: { authorization: 'Bearer aaa.bbbbbbbbbbbbb.ccc' },
  });
  expect(await verifySummerOidcRequest(new Request('https://example.com'))).toBe(false);
  jest
    .mocked(jwtVerify)
    .mockResolvedValue({ payload: { project_id: SUMMER_OIDC.projectId } } as never);
  expect(await verifySummerOidcRequest(valid)).toBe(true);
  expect(createRemoteJWKSet).toHaveBeenCalledTimes(1);
  expect(jwtVerify).toHaveBeenCalledWith(
    'aaa.bbbbbbbbbbbbb.ccc',
    expect.any(Function),
    expect.objectContaining({
      issuer: SUMMER_OIDC.issuer,
      audience: SUMMER_OIDC.audience,
      subject: SUMMER_OIDC.subject,
      algorithms: ['RS256'],
      requiredClaims: ['exp', 'iat'],
    }),
  );
  jest
    .mocked(jwtVerify)
    .mockResolvedValueOnce({ payload: { project_id: 'wrong-project' } } as never);
  expect(await verifySummerOidcRequest(valid)).toBe(false);
  jest.mocked(jwtVerify).mockRejectedValueOnce(new Error('invalid signature'));
  expect(await verifySummerOidcRequest(valid)).toBe(false);
});

it('removes freeform health details even if a future caller bypasses capture', async () => {
  const fetcher = jest.fn().mockResolvedValue(Response.json({ result: { status: 'replay' } }));
  await createSummerVoiceHandoff(env, fetcher).forward({
    ...event,
    text: 'My weight is 93kg. Refund please',
    subject: 'Diagnosis private',
    who: 'patient with private diagnosis',
    name: 'Private',
  });
  const sent = JSON.parse(fetcher.mock.calls[0][1].body);
  expect(sent).toMatchObject({ who: 'LogYourBody customer', urgentReasons: ['billing'] });
  expect(sent).not.toHaveProperty('name');
  expect(sent).not.toHaveProperty('subject');
  expect(JSON.stringify(sent)).not.toMatch(/93kg|Diagnosis|diagnosis|patient|Private/);
});
