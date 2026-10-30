/** @jest-environment node */

import { createHealthVaultHttpHandlers } from './http';
import { sentinelHits } from './payload-audit';
import { createHealthVaultService } from './service';
import { MemoryHealthVaultStore, tokenHash } from './session-store';
import type { HealthVaultReader, VaultSnapshot } from './types';
import { HEALTH_VAULT_WIDGET_DOMAIN } from './constants';

const ORIGIN = 'https://www.logyourbody.com';
const BYTES = new TextEncoder().encode('SENTINEL_BYTES_9f3a');

function seed(): VaultSnapshot {
  return {
    dexa: [
      { id: 'dx1', measuredOn: '2026-01-01', bodyFatPercent: 17.3417, leanMassKg: 60.5 },
      { id: 'dx2', measuredOn: '2026-02-01', bodyFatPercent: 16.2, leanMassKg: 61.25 },
    ],
    photos: [{ id: 'ph_SENTINEL', bytes: BYTES, contentType: 'image/png' }],
    weighIns: [{ id: 'w1', measuredOn: '2026-02-02', weightKg: 81.2229 }],
  };
}

function harness(options: { enabled?: boolean } = {}) {
  let nowMs = Date.parse('2026-03-01T00:00:00.000Z');
  const now = () => new Date(nowMs);
  const store = new MemoryHealthVaultStore();
  const reader: HealthVaultReader = { read: async () => seed() };
  const service = createHealthVaultService({ reader, store, now });
  const http = createHealthVaultHttpHandlers({
    enabled: () => options.enabled ?? true,
    service,
    media: {
      read(token: string) {
        return store.readMedia(tokenHash(token), now());
      },
    },
    apiOrigin: () => ORIGIN,
  });
  return {
    service,
    store,
    http,
    advance(ms: number) {
      nowMs += ms;
    },
    now,
  };
}

function request(path: string, body?: unknown, origin = HEALTH_VAULT_WIDGET_DOMAIN) {
  return new Request(`${ORIGIN}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { origin, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe('health vault direct fetch', () => {
  it('keeps measurements out of open and serves them only on redeem', async () => {
    expect(JSON.stringify(17.3417)).toBe('17.3417');
    expect(JSON.stringify(81.2229)).toBe('81.2229');
    const { service } = harness();

    const opened = await service.open('subject-a');
    expect(opened.ok).toBe(true);
    if (!opened.ok) return;
    expect(opened.counts).toEqual({ dexa: 2, photos: 1, weigh_ins: 1 });
    expect(Object.keys(opened).sort()).toEqual(['counts', 'handle', 'ok']);
    expect(sentinelHits(opened)).toEqual([]);

    const redeemed = await service.redeem(opened.handle, ORIGIN);
    expect(redeemed.ok).toBe(true);
    if (!redeemed.ok) return;
    expect(sentinelHits(redeemed).sort()).toEqual(['17.3417', '81.2229', 'ph_SENTINEL']);
    expect(JSON.stringify(redeemed)).not.toContain('SENTINEL_BYTES_9f3a');
    expect(redeemed.view.photos[0]?.imageUrl).toContain('/api/health-vault/media?token=');

    expect((await service.redeem(opened.handle, ORIGIN)).ok).toBe(false);
  });

  it('expires the handle at five minutes', async () => {
    const h = harness();
    const opened = await h.service.open('subject-a');
    if (!opened.ok) throw new Error('open failed');
    h.advance(5 * 60 * 1000);
    expect((await h.service.redeem(opened.handle, ORIGIN)).ok).toBe(false);
    expect(sentinelHits(await h.service.redeem(opened.handle, ORIGIN))).toEqual([]);
  });

  it('shares only the confirmed fields and logs the consent without numbers', async () => {
    const h = harness();
    const opened = await h.service.open('subject-a');
    if (!opened.ok) throw new Error('open failed');
    const redeemed = await h.service.redeem(opened.handle, ORIGIN);
    if (!redeemed.ok) throw new Error('redeem failed');

    expect(
      (
        await h.service.confirm({
          confirmToken: redeemed.view.confirmToken,
          fields: [],
        })
      ).ok,
    ).toBe(false);

    const confirmed = await h.service.confirm({
      confirmToken: redeemed.view.confirmToken,
      fields: ['body_fat'],
    });
    expect(confirmed.ok).toBe(true);
    if (!confirmed.ok) return;

    expect((await h.service.share('other-subject', confirmed.consentId)).ok).toBe(false);
    const shared = await h.service.share('subject-a', confirmed.consentId);
    expect(shared.ok).toBe(true);
    if (!shared.ok) return;
    expect(shared.fields).toEqual(['body_fat']);
    expect(shared.summary.body_fat?.first).toBe(17.3417);
    expect(shared.summary.weight).toBeUndefined();
    expect(shared.summary.lean_mass).toBeUndefined();
    expect(JSON.stringify(shared)).not.toContain('81.2229');
    expect(JSON.stringify(shared)).not.toContain('ph_SENTINEL');
    expect(JSON.stringify(shared)).not.toContain('SENTINEL_BYTES_9f3a');
    expect((await h.service.share('subject-a', confirmed.consentId)).ok).toBe(false);
    expect(sentinelHits(h.store.events)).toEqual([]);
    expect(h.store.events[0]).toMatchObject({
      subject: 'subject-a',
      fields: ['body_fat'],
      consentId: confirmed.consentId,
    });
  });

  it('answers 404 with an empty body when the gate is closed, even if the body has a sentinel', async () => {
    const h = harness({ enabled: false });
    const response = await h.http.view(request('/api/health-vault/view', { handle: '17.34170' }));
    expect(response.status).toBe(404);
    expect(await response.text()).toBe('');
  });

  it('redeems over HTTP, confirms without echoing measurements, and serves photo bytes inline', async () => {
    const h = harness();
    const opened = await h.service.open('subject-a');
    if (!opened.ok) throw new Error('open failed');

    const denied = await h.http.view(
      request('/api/health-vault/view', { handle: 'missing-handle' }, 'https://evil.example'),
    );
    expect(denied.status).toBe(404);
    expect(denied.headers.get('access-control-allow-origin')).toBeNull();

    const view = await h.http.view(request('/api/health-vault/view', { handle: opened.handle }));
    expect(view.status).toBe(200);
    expect(view.headers.get('access-control-allow-origin')).toBe(HEALTH_VAULT_WIDGET_DOMAIN);
    expect(view.headers.get('cache-control')).toBe('no-store');
    const viewBody = await view.json();
    expect(sentinelHits(viewBody).sort()).toEqual(['17.3417', '81.2229', 'ph_SENTINEL']);
    expect(JSON.stringify(viewBody)).not.toContain('SENTINEL_BYTES_9f3a');

    const again = await h.http.view(request('/api/health-vault/view', { handle: opened.handle }));
    expect(again.status).toBe(404);
    expect(await again.text()).toBe('');

    const mediaUrl = new URL(viewBody.photos[0].imageUrl as string);
    const media = await h.http.media(new Request(mediaUrl, { headers: { origin: ORIGIN } }));
    expect(media.status).toBe(200);
    expect(media.headers.get('content-type')).toBe('image/png');
    expect(media.headers.get('content-disposition')).toBe('inline');
    expect(media.headers.get('x-content-type-options')).toBe('nosniff');
    expect(media.headers.get('content-disposition')).not.toContain('ph_SENTINEL');
    expect(await media.text()).toBe('SENTINEL_BYTES_9f3a');

    const bad = await h.http.consents(
      request('/api/health-vault/consents', {
        confirmToken: viewBody.confirmToken,
        fields: ['body_fat'],
        bodyFatPercent: 17.3417,
      }),
    );
    expect(bad.status).toBe(400);
    expect(sentinelHits(await bad.json())).toEqual([]);

    const consent = await h.http.consents(
      request('/api/health-vault/consents', {
        confirmToken: viewBody.confirmToken,
        fields: ['body_fat'],
      }),
    );
    expect(consent.status).toBe(200);
    expect(Object.keys(await consent.json())).toEqual(['consentId']);
  });

  it('allows the sandbox, the API origin, and localhost, and rejects other origins', async () => {
    const h = harness();
    const preflight = await h.http.options(
      new Request(`${ORIGIN}/api/health-vault/view`, {
        method: 'OPTIONS',
        headers: { origin: 'http://localhost:3000' },
      }),
    );
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get('access-control-allow-origin')).toBe('http://localhost:3000');

    const closed = harness({ enabled: false });
    const hidden = await closed.http.options(
      new Request(`${ORIGIN}/api/health-vault/view`, {
        method: 'OPTIONS',
        headers: { origin: HEALTH_VAULT_WIDGET_DOMAIN },
      }),
    );
    expect(hidden.status).toBe(404);
  });
});
