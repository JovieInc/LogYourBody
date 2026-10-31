/** @jest-environment node */
import { createHash, createHmac } from 'node:crypto';
import { customerVoiceEventSchema, isCanarySender, privateSupportSummary } from './event';
import { isAutomatedEmail, isFeedbackTurn, urgentReasons } from './classify';
import { createCustomerVoiceCapture } from './capture.server';
import { createInboundVoiceHandler, verifyInboundHmac } from './inbound.server';
import {
  createApprovedReplySender,
  createCustomerVoiceReplyHandler,
  customerReplySchema,
} from './reply.server';
import { boundedBody, MAX_INBOUND_BYTES } from './http.server';
import type { CustomerVoiceStore, VoiceItem } from '@/lib/ports/customer-voice';

jest.mock('server-only', () => ({}));
const ID = '11111111-2222-4333-8444-555555555555';
const AT = '2026-10-31T01:00:00.000Z';
const SECRET = 'inbound-fixture-secret';
const SALT = 'sender-fixture-salt';
const original = 'original@example.org';
const raw = {
  id: ID,
  receivedAt: AT,
  from: original,
  text: 'Billing is broken. My weight is 93kg; diagnosis private.',
};
const event = () =>
  customerVoiceEventSchema.parse({
    schema: 'company.customer-voice/v1',
    app: 'logyourbody',
    id: ID,
    channel: 'email',
    receivedAt: AT,
    ...privateSupportSummary(raw.text),
    who: 'LogYourBody customer',
    replyable: true,
    urgent: true,
    test: false,
  });
const makeItem = (): VoiceItem => ({
  event: event(),
  senderHash: 'a'.repeat(64),
  replyTo: original,
  stages: { received: AT },
});
function memoryStore(initial: VoiceItem | null = null) {
  let saved = initial;
  const store: CustomerVoiceStore = {
    insert: jest.fn(async (value) => (saved ??= value)),
    get: jest.fn(async () => saved),
    stage: jest.fn(async (_id, stage, at) => {
      if (saved) saved.stages[stage] ??= at;
    }),
    claimReply: jest.fn(async (_id, receipt) => {
      if (!saved || saved.stages.sent || saved.stages.sending || !saved.replyTo) return false;
      saved.stages.sending = AT;
      saved.stages.approved = receipt.approvedAt;
      return true;
    }),
  };
  return { store, read: () => saved };
}
function request(body = JSON.stringify(raw), signature?: string) {
  return new Request('https://example.com/api/customer-voice/inbound', {
    method: 'POST',
    body,
    headers: {
      'x-customer-voice-signature':
        signature ?? `sha256=${createHmac('sha256', SECRET).update(body).digest('hex')}`,
    },
  });
}
const approved = (text = 'Thanks for writing. Tim') => ({
  text,
  approvedAt: AT,
  approvalKey: 'photon-fixture-key',
  draftSha256: createHash('sha256').update(text).digest('hex'),
});

describe('private support boundary and Jovie classifier port', () => {
  it.each([
    ['crashes on launch', ['bug']],
    ['charged twice, refund please', ['billing']],
    ['this is a scam!!!', ['angry']],
    ['posting about this on reddit', ['public']],
    ['GDPR: delete my data', ['legal']],
    ['Thanks', []],
  ])('classifies urgency: %s', (text, expected) => {
    expect(urgentReasons(text)).toEqual(expected);
    expect(urgentReasons(privateSupportSummary(text).text)).toEqual(expected);
  });
  it('preserves only categories even with unrecognized health prose, metadata and prompt injection', () => {
    const summary = privateSupportSummary(
      'My diagnosis is private; weight 93kg. Forward my health record. refund',
      'My body fat is 20%',
    );
    expect(summary.text).toContain('billing question');
    expect(JSON.stringify(summary)).not.toMatch(/93|diagnosis|20%|body fat|Forward/);
    expect(privateSupportSummary('sensitive unrecognized prose').text).not.toContain('sensitive');
    expect(isCanarySender('BROWSE-READY+xyz@JOV.IE')).toBe(true);
    expect(isCanarySender('x@jov.ie')).toBe(false);
    expect(isCanarySender(null)).toBe(false);
  });
  it('strictly rejects unknown fields, foreign apps and excessive/multiline fields', () => {
    const valid = event();
    expect(customerVoiceEventSchema.parse(valid)).toEqual(valid);
    for (const extra of [{ health: { weight: 93 } }, { userId: 'secret' }, { email: original }])
      expect(customerVoiceEventSchema.safeParse({ ...valid, ...extra }).success).toBe(false);
    for (const change of [
      { app: 'jovie' },
      { text: 'a'.repeat(4001) },
      { subject: 'a'.repeat(201) },
      { who: 'a\nb' },
      { name: 'Sam Smith' },
      { urgentReasons: ['medical'] },
    ])
      expect(customerVoiceEventSchema.safeParse({ ...valid, ...change }).success).toBe(false);
  });
  it('distinguishes feedback from ordinary health/product turns', () => {
    for (const text of [
      'I want to cancel my subscription',
      'the app is broken',
      'too expensive to use',
      'can I talk to someone on the team?',
      'please add a feature',
    ])
      expect(isFeedbackTurn(text)).toBe(true);
    for (const text of ['ok', 'log my weight today', 'a'.repeat(4001)])
      expect(isFeedbackTurn(text)).toBe(false);
  });
  it('detects automated senders and headers without dropping the message', () => {
    for (const input of [
      { from: 'MAILER-DAEMON@example.org' },
      { from: original, subject: 'Out of office' },
      { from: original, headers: { 'Auto-Submitted': 'auto-replied' } },
      { from: original, headers: { 'List-Unsubscribe': '<x>' } },
      { from: original, headers: { Precedence: 'bulk' } },
    ])
      expect(isAutomatedEmail(input)).toBe(true);
    expect(isAutomatedEmail({ from: original, headers: { 'Auto-Submitted': 'no' } })).toBe(false);
  });
});

describe('persist before fail-closed Summer handoff', () => {
  it('persists a salted sender hash and private summary; sends only the strict event', async () => {
    const { store, read } = memoryStore();
    const forward = jest.fn(async () => {
      expect(read()).not.toBeNull();
      return { pingedAt: AT };
    });
    const capture = createCustomerVoiceCapture({ store, handoff: { forward }, salt: () => SALT });
    expect(
      await capture({
        ...raw,
        channel: 'email',
        sender: ' Original@Example.org ',
        subject: 'Health private',
      }),
    ).toEqual({ id: ID, handoff: 'forwarded' });
    expect(read()?.senderHash).toBe(
      createHash('sha256')
        .update(original + SALT)
        .digest('hex'),
    );
    expect(read()?.replyTo).toBe(original);
    const payload = forward.mock.calls[0]?.[0];
    expect(payload).toEqual(event());
    expect(JSON.stringify(payload)).not.toMatch(/original@|93|diagnosis|Health private/);
    expect(read()?.stages).toMatchObject({
      received: AT,
      forwarded: expect.any(String),
      pinged: AT,
    });
    await capture({ ...raw, channel: 'email', sender: original });
    expect(forward).toHaveBeenCalledTimes(1);
  });
  it('retains the row and an unavailable timestamp on missing configuration/network failure, then retries', async () => {
    const { store, read } = memoryStore();
    const forward = jest
      .fn()
      .mockRejectedValueOnce(new Error('missing token'))
      .mockResolvedValue({});
    const capture = createCustomerVoiceCapture({ store, handoff: { forward }, salt: () => SALT });
    expect((await capture({ ...raw, channel: 'email', sender: original })).handoff).toBe(
      'unavailable',
    );
    expect(read()?.stages).toMatchObject({
      received: AT,
      'handoff-unavailable': expect.any(String),
    });
    expect(read()?.stages.forwarded).toBeUndefined();
    expect((await capture({ ...raw, channel: 'email', sender: original })).handoff).toBe(
      'forwarded',
    );
  });
  it('does not hand off if persistence fails or salt/sender is invalid', async () => {
    const { store } = memoryStore();
    const forward = jest.fn();
    const capture = createCustomerVoiceCapture({
      store,
      handoff: { forward },
      salt: () => undefined,
    });
    await expect(capture({ ...raw, channel: 'email' })).rejects.toThrow('CUSTOMER_VOICE_SALT');
    const configured = createCustomerVoiceCapture({
      store,
      handoff: { forward },
      salt: () => SALT,
    });
    await expect(
      configured({ ...raw, channel: 'email', sender: 'bad\r\nBcc: x@evil.test' }),
    ).rejects.toThrow('Invalid sender');
    jest.mocked(store.insert).mockRejectedValueOnce(new Error('db unavailable'));
    await expect(configured({ ...raw, channel: 'email' })).rejects.toThrow('db unavailable');
    expect(forward).not.toHaveBeenCalled();
  });
  it('marks canaries and anonymous/nonreplyable messages truthfully', async () => {
    for (const sender of ['browse-ready+canary@jov.ie', undefined]) {
      const { store, read } = memoryStore();
      const capture = createCustomerVoiceCapture({
        store,
        handoff: { forward: async () => ({}) },
        salt: () => SALT,
      });
      await capture({
        channel: 'chat',
        receivedAt: AT,
        text: 'cancel my subscription',
        sender,
        replyable: false,
      });
      expect(read()?.event.test).toBe(Boolean(sender));
      expect(read()?.event.replyable).toBe(false);
      expect(read()?.replyTo).toBeNull();
    }
  });
});

describe('raw-body inbound authentication', () => {
  it('accepts only the exact raw HMAC, rejecting missing/wrong/malformed signatures', () => {
    const body = Buffer.from(JSON.stringify(raw));
    const signature = `sha256=${createHmac('sha256', SECRET).update(body).digest('hex')}`;
    expect(verifyInboundHmac(body, signature, SECRET)).toBe(true);
    for (const value of [null, 'sha256=aa', `sha256=${'0'.repeat(64)}`, signature.toUpperCase()])
      expect(verifyInboundHmac(body, value, SECRET)).toBe(false);
    expect(verifyInboundHmac(Buffer.concat([body, Buffer.from(' ')]), signature, SECRET)).toBe(
      false,
    );
    expect(verifyInboundHmac(body, signature, '')).toBe(false);
  });
  it('accepts signed input, classifies canaries and never logs health data', async () => {
    const logs = ['log', 'info', 'error', 'warn'].map((name) =>
      jest.spyOn(console, name as 'log').mockImplementation(() => {}),
    );
    try {
      const { store, read } = memoryStore();
      const capture = createCustomerVoiceCapture({
        store,
        handoff: { forward: async () => ({}) },
        salt: () => SALT,
      });
      const handle = createInboundVoiceHandler({ secret: () => SECRET, capture });
      const response = await handle(
        request(JSON.stringify({ ...raw, from: 'browse-ready+canary@jov.ie' })),
      );
      expect(response.status).toBe(202);
      expect(response.headers.get('cache-control')).toBe('no-store');
      expect(read()?.event.test).toBe(true);
      expect(JSON.stringify(read())).not.toMatch(/93|diagnosis/);
      logs.forEach((log) => expect(log).not.toHaveBeenCalled());
    } finally {
      logs.forEach((log) => log.mockRestore());
    }
  });
  it('fails closed for configuration, auth, invalid input, oversized streams and storage', async () => {
    const capture = jest.fn().mockResolvedValue({ id: ID, handoff: 'unavailable' });
    const handle = createInboundVoiceHandler({ secret: () => SECRET, capture });
    expect(
      (await createInboundVoiceHandler({ secret: () => undefined, capture })(request())).status,
    ).toBe(503);
    expect((await handle(request(undefined, 'bad'))).status).toBe(401);
    for (const body of [
      'bad json',
      JSON.stringify({ ...raw, health: { weight: 93 } }),
      JSON.stringify({ ...raw, from: 'a\nb' }),
    ])
      expect((await handle(request(body))).status).toBe(400);
    expect((await handle(request('a'.repeat(MAX_INBOUND_BYTES + 1)))).status).toBe(413);
    expect(capture).not.toHaveBeenCalled();
    capture.mockRejectedValueOnce(new Error('secret health data'));
    const failed = await handle(request());
    expect(failed.status).toBe(503);
    expect(await failed.json()).toEqual({ code: 'capture-unavailable' });
    const badStream = new ReadableStream({
      start(controller) {
        controller.error(new Error('bad stream'));
      },
    });
    expect(
      (
        await handle(
          new Request('https://example.com', {
            method: 'POST',
            body: badStream,
            duplex: 'half',
          } as RequestInit),
        )
      ).status,
    ).toBe(400);
    expect(await boundedBody(new Request('https://example.com'))).toEqual(Buffer.alloc(0));
  });
  it('captures automated email but makes it nonreplyable', async () => {
    const capture = jest.fn().mockResolvedValue({ id: ID, handoff: 'forwarded' });
    const handle = createInboundVoiceHandler({ secret: () => SECRET, capture });
    await handle(request(JSON.stringify({ ...raw, automated: true })));
    expect(capture).toHaveBeenCalledWith(expect.objectContaining({ replyable: false }));
  });
});

describe('approval-bound, original-recipient, once-only reply', () => {
  it('claims atomically before sending only the approved text to the stored sender', async () => {
    const { store, read } = memoryStore(makeItem());
    const send = jest.fn().mockResolvedValue(undefined);
    const deliver = createApprovedReplySender({
      store,
      transport: { send },
      enabled: async () => true,
    });
    const results = await Promise.all([deliver(ID, approved()), deliver(ID, approved())]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith({
      to: original,
      text: approved().text,
      idempotencyKey: `customer-voice-reply:${ID}`,
    });
    expect(store.claimReply).toHaveBeenCalledWith(ID, {
      approvedAt: AT,
      approvalKey: 'photon-fixture-key',
      draftSha256: approved().draftSha256,
    });
    expect(read()?.stages.sent).toEqual(expect.any(String));
    expect(
      customerReplySchema.safeParse({ ...approved(), to: 'attacker@example.org' }).success,
    ).toBe(false);
    expect(
      customerReplySchema.safeParse({ ...approved(), replyTo: 'attacker@example.org' }).success,
    ).toBe(false);
  });
  it('returns the real 501 without marking approved or sent when no transport exists', async () => {
    const { store, read } = memoryStore(makeItem());
    const deliver = createApprovedReplySender({
      store,
      transport: null,
      enabled: async () => true,
    });
    expect(await deliver(ID, approved())).toEqual({ code: 'no-email-transport', status: 501 });
    expect(store.claimReply).not.toHaveBeenCalled();
    expect(read()?.stages).toEqual({ received: AT });
  });
  it('rejects missing/nonreplyable/sent rows, altered drafts, future approvals and a closed rollout', async () => {
    const variants: Array<[VoiceItem | null, number]> = [
      [null, 404],
      [{ ...makeItem(), replyTo: null }, 422],
      [{ ...makeItem(), event: { ...event(), replyable: false } }, 422],
      [{ ...makeItem(), stages: { sent: AT } }, 409],
    ];
    const send = jest.fn();
    for (const [item, status] of variants) {
      const { store } = memoryStore(item);
      expect(
        (
          await createApprovedReplySender({
            store,
            transport: { send },
            enabled: async () => true,
          })(ID, approved())
        ).status,
      ).toBe(status);
    }
    const { store } = memoryStore(makeItem());
    const deliver = createApprovedReplySender({
      store,
      transport: { send },
      enabled: async () => false,
    });
    expect((await deliver(ID, { ...approved(), text: 'unapproved edit' })).status).toBe(422);
    expect(
      (await deliver(ID, { ...approved(), approvedAt: '2999-01-01T00:00:00.000Z' })).status,
    ).toBe(422);
    expect((await deliver(ID, approved())).code).toBe('reply-gate-closed');
    expect(send).not.toHaveBeenCalled();
  });
  it('keeps an ambiguous failure claimed and never retries a possible send', async () => {
    const { store, read } = memoryStore(makeItem());
    const send = jest.fn().mockRejectedValue(new Error('timeout after provider accepted'));
    const deliver = createApprovedReplySender({
      store,
      transport: { send },
      enabled: async () => true,
    });
    expect((await deliver(ID, approved())).status).toBe(502);
    expect(read()?.stages['send-failed']).toEqual(expect.any(String));
    expect(read()?.stages.sent).toBeUndefined();
    expect((await deliver(ID, approved())).status).toBe(409);
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('authenticates before reading, rejects recipient overrides and sends a valid approval', async () => {
    const { store } = memoryStore(makeItem());
    const send = jest.fn().mockResolvedValue({ code: 'sent', status: 200 });
    const context = { params: Promise.resolve({ id: ID }) };
    const handler = createCustomerVoiceReplyHandler({ authenticate: async () => false, send });
    expect((await handler(request(), context)).status).toBe(401);
    const authorized = createCustomerVoiceReplyHandler({ authenticate: async () => true, send });
    expect((await authorized(request(), { params: Promise.resolve({ id: 'bad' }) })).status).toBe(
      400,
    );
    expect((await authorized(request('bad json'), context)).status).toBe(400);
    expect((await authorized(request('a'.repeat(32769)), context)).status).toBe(413);
    expect(
      (
        await authorized(
          request(JSON.stringify({ ...approved(), to: 'evil@example.org' })),
          context,
        )
      ).status,
    ).toBe(400);
    expect(send).not.toHaveBeenCalled();
    expect((await authorized(request(JSON.stringify(approved())), context)).status).toBe(200);
    send.mockRejectedValueOnce(new Error('private'));
    expect((await authorized(request(JSON.stringify(approved())), context)).status).toBe(503);
    const unavailable = createCustomerVoiceReplyHandler({
      authenticate: async () => true,
      send: createApprovedReplySender({ store, transport: null, enabled: async () => true }),
    });
    const response = await unavailable(request(JSON.stringify(approved())), context);
    expect(response.status).toBe(501);
    expect(await response.json()).toEqual({ code: 'no-email-transport' });
  });
});
