import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { test } from 'node:test';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import {
  verifySummerOidcRequest,
  SUMMER_OIDC,
} from '../src/lib/adapters/customer-voice-summer.server';
import worker from '../../../workers/customer-voice-email/index.js';

// This file runs in the existing web test/test:ci scripts, under react-server
// conditions so server-only modules remain server-side. No network or credentials.
test('real RS256 OIDC verifies issuer, audience, subject, project, expiry and signature', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'fixture', alg: 'RS256', use: 'sig' };
  const keys = createLocalJWKSet({ keys: [jwk] });
  async function token(patch: Record<string, unknown> = {}, key = privateKey) {
    return new SignJWT({
      iss: SUMMER_OIDC.issuer,
      aud: SUMMER_OIDC.audience,
      sub: SUMMER_OIDC.subject,
      project_id: SUMMER_OIDC.projectId,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 300,
      ...patch,
    })
      .setProtectedHeader({ alg: 'RS256', kid: 'fixture' })
      .sign(key);
  }
  const verifies = (value: string) =>
    verifySummerOidcRequest(
      new Request('https://example.com', { headers: { authorization: `Bearer ${value}` } }),
      keys,
    );
  assert.equal(await verifies(await token()), true);
  for (const patch of [
    { iss: 'https://evil.example' },
    { aud: 'wrong' },
    { sub: 'owner:jovie:project:other:environment:production' },
    { project_id: 'wrong' },
    { exp: 1 },
    { iat: undefined },
    { exp: undefined },
  ])
    assert.equal(await verifies(await token(patch)), false);
  const attacker = await generateKeyPair('RS256');
  assert.equal(await verifies(await token({}, attacker.privateKey)), false);
  assert.equal(await verifies('aaa.bbbbbbbbbbbbb.ccc'), false);
});

function email(raw?: string) {
  const mime =
    raw ??
    'From: Sam <original@example.org>\r\nTo: support@logyourbody.com\r\nSubject: Refund\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nCharged twice. My weight is 93kg and diagnosis private.';
  return {
    from: 'original@example.org',
    to: 'support@logyourbody.com',
    raw: new Response(mime).body!,
    rawSize: Buffer.byteLength(mime),
    headers: new Headers({ subject: 'Refund', 'message-id': '<fixture@example.org>' }),
    forward: async (_destination: string) => {},
  };
}
const env = {
  INBOUND_URL: 'https://example.com/api/customer-voice/inbound',
  FORWARD_TO: 'existing@example.org',
  CUSTOMER_VOICE_INBOUND_SECRET: 'fixture-secret',
};

test('Worker parses MIME, authenticates private summaries, forwards the original mailbox and uses stable ids', async () => {
  const previous = globalThis.fetch;
  const deliveries: Array<{ body: string; signature: string | null }> = [];
  const forwarded: string[] = [];
  globalThis.fetch = async (_url, init) => {
    deliveries.push({
      body: String(init?.body),
      signature: new Headers(init?.headers).get('x-customer-voice-signature'),
    });
    assert.equal(init?.redirect, 'error');
    return Response.json({ id: 'fixture' }, { status: 202 });
  };
  try {
    for (let i = 0; i < 2; i++) {
      const message = email();
      message.forward = async (destination) => {
        forwarded.push(destination);
      };
      await worker.email(message, env);
    }
    assert.deepEqual(forwarded, [env.FORWARD_TO, env.FORWARD_TO]);
    const payloads = deliveries.map((delivery) => JSON.parse(delivery.body));
    assert.equal(payloads[0].id, payloads[1].id);
    assert.match(payloads[0].text, /billing question/);
    for (const delivery of deliveries) {
      assert.equal(
        delivery.signature,
        `sha256=${createHmac('sha256', env.CUSTOMER_VOICE_INBOUND_SECRET).update(delivery.body).digest('hex')}`,
      );
      assert.doesNotMatch(delivery.body, /93kg|diagnosis|weight|Sam|Subject|Content-Type/);
    }
    const html = email(
      'From: a@example.org\r\nSubject: Bug\r\nContent-Type: multipart/alternative; boundary=x\r\n\r\n--x\r\nContent-Type: text/html\r\nContent-Transfer-Encoding: base64\r\n\r\nPHA+QXBwIGlzIGJyb2tlbi4gV2VpZ2h0IDkza2cuPC9wPg==\r\n--x--',
    );
    await worker.email(html, env);
    assert.match(JSON.parse(deliveries[2].body).text, /bug report/);
    assert.doesNotMatch(deliveries[2].body, /93kg|Weight|<p>/);
  } finally {
    globalThis.fetch = previous;
  }
});

test('Worker forwards even when ingress fails, retries the same signed event, and reports failure', async () => {
  const previous = globalThis.fetch;
  let forwards = 0;
  const attempts: string[] = [];
  globalThis.fetch = async (_url, init) => {
    attempts.push(String(init?.body));
    return new Response(null, { status: 503 });
  };
  try {
    const message = email();
    message.forward = async () => {
      forwards++;
    };
    await assert.rejects(worker.email(message, env), /delivery-incomplete/);
    assert.equal(forwards, 1);
    assert.equal(attempts.length, 3);
    assert.equal(new Set(attempts).size, 1);
    await assert.rejects(
      worker.email(message, { ...env, CUSTOMER_VOICE_INBOUND_SECRET: '' }),
      /delivery-incomplete/,
    );
    assert.equal(forwards, 2);
  } finally {
    globalThis.fetch = previous;
  }
});

test('Worker captures even when mailbox forwarding fails and handles oversized messages without parsing', async () => {
  const previous = globalThis.fetch;
  const bodies: string[] = [];
  globalThis.fetch = async (_url, init) => {
    bodies.push(String(init?.body));
    return new Response(null, { status: 202 });
  };
  try {
    const message = email();
    message.rawSize = 2 * 1024 * 1024;
    message.forward = async () => {
      throw new Error('forward unavailable');
    };
    await assert.rejects(worker.email(message, env), /delivery-incomplete/);
    assert.equal(bodies.length, 1);
    assert.match(JSON.parse(bodies[0]).text, /billing question/);
    assert.doesNotMatch(bodies[0], /93kg|diagnosis/);
  } finally {
    globalThis.fetch = previous;
  }
});
