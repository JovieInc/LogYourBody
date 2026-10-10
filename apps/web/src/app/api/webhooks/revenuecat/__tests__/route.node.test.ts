/** @jest-environment node */
import { createHmac } from 'node:crypto';
import type { RevenueEventStore } from '@/lib/ports/revenue-events';
import type { RevenueCatEnvelope } from '@/lib/revenuecat/events';
import { createRevenueCatHandler, MAX_REVENUECAT_BODY_BYTES } from '../route-handlers';

const signingSecret = 'synthetic-signing-fixture';
const now = new Date('2026-10-09T12:00:00.000Z');
const signedAt = now.getTime() / 1000;
const envelope = (overrides: Record<string, unknown> = {}) => ({
  api_version: '1.0',
  event: {
    id: 'event-one',
    app_id: 'app-fixture',
    type: 'INITIAL_PURCHASE',
    event_timestamp_ms: now.getTime(),
    environment: 'PRODUCTION',
    store: 'APP_STORE',
    transaction_id: 'transaction-one',
    original_transaction_id: 'subscription-one',
    app_user_id: 'subject-fixture',
    product_id: 'com.logyourbody.app.pro1.monthly.3daytrial',
    period_type: 'NORMAL',
    purchased_at_ms: now.getTime(),
    expiration_at_ms: new Date('2026-11-09T12:00:00.000Z').getTime(),
    price: 9.99,
    price_in_purchased_currency: 8.99,
    currency: 'EUR',
    is_family_share: false,
    ...overrides,
  },
});

function signedRequest(body = JSON.stringify(envelope()), timestamp = signedAt) {
  const signature = createHmac('sha256', signingSecret)
    .update(`${timestamp}.${body}`)
    .digest('hex');
  return new Request('http://localhost/api/webhooks/revenuecat', {
    method: 'POST',
    body,
    headers: {
      'content-type': 'application/json',
      'x-revenuecat-webhook-signature': `t=${timestamp},v1=${signature}`,
    },
  });
}

function harness() {
  const rows = new Map<string, { envelope: RevenueCatEnvelope; fingerprint: string }>();
  const store: RevenueEventStore = {
    async insert(value, fingerprint) {
      const key = `${value.event.app_id}:${value.event.id}`;
      const prior = rows.get(key);
      if (prior) return prior.fingerprint === fingerprint ? 'duplicate' : 'conflict';
      rows.set(key, { envelope: value, fingerprint });
      return 'stored';
    },
  };
  const configuration = { signingSecret, allowedAppIds: ['app-fixture'] };
  return {
    rows,
    store,
    configuration,
    handler: createRevenueCatHandler({ store, configuration: () => configuration, now: () => now }),
  };
}

describe('RevenueCat signed delivery ingestion', () => {
  it.each(['secret', 'apps'])('fails closed without configured %s', async (missing) => {
    const h = harness();
    if (missing === 'secret') h.configuration.signingSecret = '';
    else h.configuration.allowedAppIds = [];
    expect((await h.handler(signedRequest())).status).toBe(503);
    expect(h.rows.size).toBe(0);
  });

  it.each(['missing', 'bad-hex', 'short', 'duplicate', 'stale', 'future', 'wrong-secret'])(
    'rejects an invalid signature (%s) before storage',
    async (mode) => {
      const h = harness();
      const req = signedRequest();
      if (mode === 'missing') req.headers.delete('x-revenuecat-webhook-signature');
      else if (mode === 'stale' || mode === 'future') {
        const invalid = signedRequest(undefined, signedAt + (mode === 'stale' ? -301 : 301));
        expect((await h.handler(invalid)).status).toBe(401);
        expect(h.rows.size).toBe(0);
        return;
      } else
        req.headers.set(
          'x-revenuecat-webhook-signature',
          (
            {
              'bad-hex': `t=${signedAt},v1=${'z'.repeat(64)}`,
              short: `t=${signedAt},v1=a`,
              duplicate: `t=${signedAt},t=${signedAt},v1=${'a'.repeat(64)}`,
              'wrong-secret': `t=${signedAt},v1=${'0'.repeat(64)}`,
            } as Record<string, string>
          )[mode]!,
        );
      expect((await h.handler(req)).status).toBe(401);
      expect(h.rows.size).toBe(0);
    },
  );

  it('authenticates exact raw bytes and allows a freshly signed retry of an old event', async () => {
    const h = harness();
    const body = JSON.stringify(envelope({ event_timestamp_ms: 1 }), null, 2) + '\n';
    const valid = signedRequest(body);
    const altered = new Request(valid.url, {
      method: 'POST',
      headers: valid.headers,
      body: body.trim(),
    });
    expect((await h.handler(altered)).status).toBe(401);
    expect((await h.handler(valid)).status).toBe(200);
    expect(h.rows.size).toBe(1);
  });

  it('bounds actual UTF-8 bytes even when Content-Length lies', async () => {
    const h = harness();
    const req = signedRequest(
      JSON.stringify(envelope({ padding: 'é'.repeat(MAX_REVENUECAT_BODY_BYTES / 2) })),
    );
    req.headers.set('content-length', '1');
    expect((await h.handler(req)).status).toBe(413);
    expect(h.rows.size).toBe(0);
  });

  it.each([
    '{',
    JSON.stringify(envelope({ price: '9.99' })),
    JSON.stringify(envelope({ id: null })),
  ])('rejects malformed signed payloads', async (body) => {
    const h = harness();
    expect((await h.handler(signedRequest(body))).status).toBe(400);
    expect(h.rows.size).toBe(0);
  });

  it('requires JSON content and an allowed app', async () => {
    const h = harness();
    const req = signedRequest();
    req.headers.set('content-type', 'text/plain');
    expect((await h.handler(req)).status).toBe(415);
    expect(
      (await h.handler(signedRequest(JSON.stringify(envelope({ app_id: 'another-app' }))))).status,
    ).toBe(403);
    expect(h.rows.size).toBe(0);
  });

  it('stores one immutable row for concurrent deliveries and detects changed identity fields', async () => {
    const h = harness();
    const responses = await Promise.all([h.handler(signedRequest()), h.handler(signedRequest())]);
    expect(responses.map((r) => r.status)).toEqual([200, 200]);
    expect((await Promise.all(responses.map((r) => r.json()))).map((r) => r.result).sort()).toEqual(
      ['duplicate', 'stored'],
    );
    const original = [...h.rows.values()];
    const changed = await h.handler(
      signedRequest(JSON.stringify(envelope({ transaction_id: 'different-transaction' }))),
    );
    expect(changed.status).toBe(409);
    expect([...h.rows.values()]).toEqual(original);
    const reformatted = await h.handler(
      signedRequest(
        JSON.stringify(
          envelope({ subscriber_attributes: { email: 'omitted@example.test' } }),
          null,
          2,
        ),
      ),
    );
    expect(reformatted.status).toBe(200);
    expect(await reformatted.json()).toEqual({ result: 'duplicate' });
    expect(JSON.stringify([...h.rows.values()])).not.toContain('omitted@example.test');
  });

  it('retains separate purchase/refund lifecycle events, sandbox and unknown events without requiring a price', async () => {
    const h = harness();
    for (const override of [
      {},
      {
        id: 'refund',
        type: 'CANCELLATION',
        cancel_reason: 'CUSTOMER_SUPPORT',
        price: -9.99,
        price_in_purchased_currency: -8.99,
      },
      { id: 'sandbox', environment: 'SANDBOX', price: 0 },
      {
        id: 'future',
        type: 'FUTURE_EVENT',
        price: null,
        currency: null,
        price_in_purchased_currency: null,
        future_field: true,
      },
    ])
      expect((await h.handler(signedRequest(JSON.stringify(envelope(override))))).status).toBe(200);
    expect(h.rows.size).toBe(4);
    expect([...h.rows.values()].map(({ envelope: value }) => value.event.price)).toEqual([
      9.99,
      -9.99,
      0,
      null,
    ]);
  });

  it('does not acknowledge before durable persistence and returns a retryable error on failure', async () => {
    const h = harness();
    let resolve!: (result: 'stored') => void;
    h.store.insert = () =>
      new Promise((done) => {
        resolve = done;
      });
    let settled = false;
    const response = h.handler(signedRequest()).then((result) => {
      settled = true;
      return result;
    });
    await new Promise((done) => setImmediate(done));
    expect(settled).toBe(false);
    resolve('stored');
    expect((await response).status).toBe(200);
    h.store.insert = async () => {
      throw new Error('database unavailable');
    };
    expect((await h.handler(signedRequest())).status).toBe(503);
  });

  it.each(['ZZZ', 'XXX'])(
    'retains signed unsupported currency %s for reporting exclusions',
    async (currency) => {
      const h = harness();
      expect((await h.handler(signedRequest(JSON.stringify(envelope({ currency }))))).status).toBe(
        200,
      );
      expect([...h.rows.values()][0]?.envelope.event.currency).toBe(currency);
    },
  );
});
