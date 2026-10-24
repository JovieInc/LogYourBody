#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { logYourBody } from '../../packages/product-registry/src/products/logyourbody.mjs';

const PUBLIC_ROUTES = [
  '/', '/about', '/brand', '/careers', '/security', '/privacy', '/terms',
  '/health-disclosure', '/support', '/delete-account', '/changelog', '/blog',
  '/signin', '/signup', '/download/ios', '/download/android',
];
const CANONICAL_ALIASES = { '/download/ios': '/' };
const BACKOFF_MS = [0, 2_000, 5_000];

// No email: even a regressed honeypot cannot turn this probe into a registration.
export const WAITLIST_HONEYPOT = Object.freeze({ website: 'production-smoke' });

function origin(value) {
  const url = new URL(value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.pathname !== '/' || url.search || url.hash) {
    throw new Error('Smoke requires an HTTP(S) origin without credentials, path, query or fragment');
  }
  return url.origin;
}

function assertMetadata(html, path) {
  const title = html.match(/<title\b[^>]*>([^<]+)<\/title>/i)?.[1]?.trim();
  if (!title?.includes(logYourBody.identity.name) || /\b404\b|not found|internal server error/i.test(title)) {
    throw new Error('Missing or invalid product title');
  }
  if (title.split(logYourBody.identity.name).length !== 2 ||
      (path !== '/' && title === `${logYourBody.identity.name} — ${logYourBody.brand.slogan}`)) {
    throw new Error('Public page needs its own title with one brand suffix');
  }
  const canonicalTags = [...html.matchAll(/<link\b[^>]*>/gi)].map(([tag]) => {
    const attributes = Object.fromEntries([...tag.matchAll(/([\w-]+)\s*=\s*["']([^"']*)["']/g)]
      .map(([, key, value]) => [key.toLowerCase(), value]));
    return attributes;
  }).filter((attributes) => attributes.rel?.toLowerCase().split(/\s+/).includes('canonical'));
  if (canonicalTags.length !== 1 || !canonicalTags[0].href) throw new Error('Missing or ambiguous canonical URL');
  const canonical = new URL(canonicalTags[0].href);
  if (canonical.origin !== new URL(logYourBody.links.home).origin ||
      canonical.pathname !== (CANONICAL_ALIASES[path] ?? path) || canonical.search || canonical.hash ||
      canonical.username || canonical.password) {
    throw new Error('Canonical URL does not identify the production site');
  }
}

export async function runWebProductionSmoke({
  deploymentUrl,
  productionUrl = logYourBody.endpoints.hosts.marketing.url,
  fetchImpl = fetch,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  timeoutMs = 10_000,
} = {}) {
  const targets = [['deployment', origin(deploymentUrl)], ['production', origin(productionUrl)]];
  const checks = [
    ...PUBLIC_ROUTES.map((path) => ({ path, method: 'GET', status: 200, metadata: true })),
    ...['/robots.txt', '/sitemap.xml'].map((path) => ({ path, method: 'GET', status: 200 })),
    { path: '/api/waitlist', method: 'POST', status: 202 },
  ];
  // Check both the immutable artifact and its public alias; collect every failure.
  return Promise.all(targets.flatMap(([target, base]) => checks.map(async (check) => {
    let error;
    for (let attempt = 0; attempt < BACKOFF_MS.length; attempt++) {
      if (attempt > 0) await sleep(BACKOFF_MS[attempt]);
      try {
        const response = await fetchImpl(new URL(check.path, base), {
          method: check.method,
          redirect: 'follow',
          signal: AbortSignal.timeout(timeoutMs),
          headers: check.method === 'POST' ? { 'Content-Type': 'application/json' } : { Accept: 'text/html' },
          ...(check.method === 'POST' ? { body: JSON.stringify(WAITLIST_HONEYPOT) } : {}),
        });
        const body = await response.text();
        if (response.status !== check.status) throw new Error(`HTTP ${response.status}; expected ${check.status}`);
        if (response.url && new URL(response.url).pathname !== check.path) throw new Error('Redirect changed the checked route');
        if (check.metadata) assertMetadata(body, check.path);
        if (check.method === 'POST' && JSON.parse(body)?.success !== true) throw new Error('Waitlist did not accept honeypot');
        return { target, origin: base, path: check.path, method: check.method, ok: true, attempts: attempt + 1 };
      } catch (failure) {
        error = failure instanceof Error ? failure.message : String(failure);
      }
    }
    return { target, origin: base, path: check.path, method: check.method, ok: false, attempts: BACKOFF_MS.length, error };
  })));
}

async function main() {
  const results = await runWebProductionSmoke({ deploymentUrl: process.env.DEPLOYMENT_URL });
  const lines = results.map((result) =>
    `${result.ok ? 'PASS' : 'FAIL'} ${result.target}: ${result.method} ${result.origin}${result.path}` +
    `${result.error ? ` — ${result.error}` : ''} (${result.attempts} attempts)`);
  console.log(lines.join('\n'));
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Web production smoke\n\n${lines.map((line) => `- ${line}`).join('\n')}\n`);
  }
  if (results.some((result) => !result.ok)) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
