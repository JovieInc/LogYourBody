import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { logYourBody } from '../../packages/product-registry/src/products/logyourbody.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const workflow = readFileSync(join(root, '.github/workflows/deploy.yml'), 'utf8');
const pages = ['/', '/privacy', '/terms', '/health-disclosure', '/support', '/download/ios'];
const paths = [...pages, '/robots.txt', '/sitemap.xml', '/api/waitlist'];
const html = (path = '/') => `<html><head><title>${logYourBody.identity.name} | Public page</title>
  <link href='${new URL(path === '/download/ios' ? '/' : path, logYourBody.links.home).href}' rel='canonical'/></head><body>Public page</body></html>`;

function healthyResponse(url) {
  const path = new URL(url).pathname;
  if (path === '/api/waitlist') return Response.json({ success: true }, { status: 202 });
  return new Response(html(path), { headers: { 'content-type': 'text/html' } });
}

async function smoke(options = {}) {
  const { runWebProductionSmoke } = await import('./web-production-smoke.mjs');
  return runWebProductionSmoke({
    deploymentUrl: 'https://deployment.example.com',
    fetchImpl: healthyResponse,
    sleep: async () => {},
    ...options,
  });
}

test('production deploy runs blocking smoke on its URL before reporting success', () => {
  const web = workflow.split('\n  web:\n')[1].split('\n  ios-beta:\n')[0];
  const step = web.match(/      - name: Smoke production deployment\n([\s\S]*?)(?=\n      - name:)/)?.[0];
  assert.ok(step, 'production deployment must run smoke');
  assert.ok(web.indexOf('id: vercel-deploy') < web.indexOf(step));
  assert.ok(web.indexOf(step) < web.indexOf('      - name: Deploy info'));
  assert.match(step, /DEPLOYMENT_URL: \$\{\{ steps.vercel-deploy.outputs.url \}\}/);
  assert.match(step, /run: node \.github\/scripts\/web-production-smoke\.mjs/);
  assert.match(step, /timeout-minutes: 3/);
  assert.doesNotMatch(step, /continue-on-error|\bif:/);
  const filter = workflow.split('            web:\n')[1].split('            ios:\n')[0];
  assert.match(filter, /'\.github\/workflows\/deploy.yml'/);
  assert.match(filter, /'\.github\/scripts\/web-production-smoke\*\.mjs'/);
  assert.equal(existsSync(join(root, '.github/workflows/web-release-loop.yml')), false);
  const router = readFileSync(join(root, '.github/workflows/remediation-signal.yml'), 'utf8');
  assert.match(router, /workflow_run:[\s\S]*- Deploy/);
});

test('both origins get every check; 307 redirects preserve the honeypot POST', async (t) => {
  const { WAITLIST_HONEYPOT } = await import('./web-production-smoke.mjs');
  const requests = [];
  async function server(handler) {
    const instance = createServer(handler);
    await new Promise((resolve) => instance.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise((resolve) => instance.close(resolve)));
    return `http://127.0.0.1:${instance.address().port}`;
  }
  function publicSurface(target) {
    return async (request, response) => {
      let body = '';
      for await (const chunk of request) body += chunk;
      requests.push({ target, path: request.url, method: request.method, body });
      if (request.url === '/api/waitlist') {
        assert.equal(request.headers['content-type'], 'application/json');
        assert.deepEqual(JSON.parse(body), WAITLIST_HONEYPOT);
        response.writeHead(202, { 'content-type': 'application/json' });
        response.end('{"success":true}');
      } else {
        assert.equal(request.headers.accept, 'text/html');
        response.writeHead(200, { 'content-type': 'text/html' });
        response.end(html(request.url));
      }
    };
  }
  const deploymentUrl = await server(publicSurface('deployment'));
  const www = await server(publicSurface('production'));
  const productionUrl = await server((request, response) => {
    response.writeHead(307, { location: `${www}${request.url}` });
    response.end();
  });
  const results = await smoke({ deploymentUrl, productionUrl, fetchImpl: fetch });
  assert.equal(results.length, paths.length * 2);
  assert.ok(results.every((result) => result.ok), JSON.stringify(results));
  for (const target of ['deployment', 'production']) {
    assert.deepEqual(requests.filter((request) => request.target === target).map((request) => request.path).sort(), [...paths].sort());
    assert.equal(requests.find((request) => request.target === target && request.path === '/api/waitlist').method, 'POST');
  }
  assert.equal('email' in WAITLIST_HONEYPOT, false, 'probe must be invalid for persistence if the trap regresses');
  assert.ok(WAITLIST_HONEYPOT.website.trim());
});

for (const [name, path, response] of [
  ['homepage 500', '/', () => new Response('', { status: 500 })],
  ['non-home route 404', '/privacy', () => new Response('', { status: 404 })],
  ['redirect to homepage', '/support', () => {
    const response = new Response(html('/support'));
    Object.defineProperty(response, 'url', { value: logYourBody.links.home });
    return response;
  }],
  ['missing title', '/support', () => new Response(html('/support').replace(/<title>.*?<\/title>/, ''))],
  ['soft 404 title', '/terms', () => new Response(html('/terms').replace('Public page', '404: Not found'))],
  ['missing canonical', '/', () => new Response(html().replace(/<link[^>]+>/, ''))],
  ['wrong canonical origin', '/', () => new Response(html().replace(logYourBody.links.home, 'https://deployment.example.com'))],
  ['wrong canonical path', '/', () => new Response(html().replace("/' rel=", "/signin' rel="))],
  ['inherited homepage canonical', '/privacy', () => new Response(html('/'))],
  ['robots failure', '/robots.txt', () => new Response('', { status: 500 })],
  ['sitemap failure', '/sitemap.xml', () => new Response('', { status: 404 })],
  ['waitlist failure', '/api/waitlist', () => Response.json({ success: false }, { status: 500 })],
  ['waitlist wrong status', '/api/waitlist', () => Response.json({ success: true })],
  ['waitlist malformed acceptance', '/api/waitlist', () => new Response('not JSON', { status: 202 })],
  ['waitlist rejected acceptance', '/api/waitlist', () => Response.json({ success: false }, { status: 202 })],
]) {
  for (const target of ['deployment', 'production']) {
    test(`${target}: ${name} fails smoke even when the other host is healthy`, async () => {
      const results = await smoke({ fetchImpl: (url) => {
        const parsed = new URL(url);
        const isDeployment = parsed.hostname === 'deployment.example.com';
        return (target === 'deployment') === isDeployment && parsed.pathname === path
          ? response() : healthyResponse(url);
      } });
      const failures = results.filter((result) => !result.ok);
      assert.equal(failures.length, 1);
      assert.equal(failures[0].target, target);
      assert.equal(failures[0].path, path);
      assert.equal(failures[0].attempts, 3);
    });
  }
}

test('network failures retry with bounded backoff and report recovery', async () => {
  let calls = 0;
  const waits = [];
  const results = await smoke({
    fetchImpl: (url, options) => {
      assert.equal(options.redirect, 'follow');
      assert.ok(options.signal instanceof AbortSignal);
      if (String(url) === 'https://deployment.example.com/') {
        calls++;
        if (calls === 1) throw new Error('network unavailable');
        if (calls === 2) return new Response('', { status: 503 });
      }
      return healthyResponse(url);
    },
    sleep: async (ms) => waits.push(ms),
  });
  assert.ok(results.every((result) => result.ok));
  assert.equal(results.find((result) => result.target === 'deployment' && result.path === '/').attempts, 3);
  assert.deepEqual(waits, [2000, 5000]);
});

test('a stalled HTTP response times out and fails after three attempts', async (t) => {
  const server = createServer(() => {});
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const results = await smoke({
    deploymentUrl: `http://127.0.0.1:${server.address().port}`,
    fetchImpl: (url, options) => new URL(url).hostname === '127.0.0.1' ? fetch(url, options) : healthyResponse(url),
    timeoutMs: 15,
  });
  assert.equal(results.filter((result) => !result.ok).length, paths.length);
  assert.ok(results.filter((result) => !result.ok).every((result) => result.attempts === 3));
});

test('missing or malformed deployment URL cannot fall back to probing only production', async () => {
  const credentialsUrl = new URL('https://example.com');
  credentialsUrl.username = 'smoke';
  credentialsUrl.password = 'fixture';
  for (const deploymentUrl of ['', undefined, 'not-a-url', credentialsUrl.href, 'https://example.com/path']) {
    await assert.rejects(smoke({ deploymentUrl }));
  }
});

test('the exact workflow command exits nonzero and writes smoke failures to the run summary', () => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-web-smoke-'));
  try {
    const preload = join(directory, 'fetch.mjs');
    writeFileSync(preload, `const pages = ${JSON.stringify(Object.fromEntries(pages.map((path) => [path, html(path)])))};
    globalThis.fetch = async (url) => {
      if (new URL(url).pathname === '/api/waitlist') return Response.json({success:true}, {status:202});
      return new Response(pages[new URL(url).pathname] ?? '', {status: new URL(url).pathname === '/support' ? 500 : 200});
    };`);
    const command = workflow.match(/run: (node \.github\/scripts\/web-production-smoke\.mjs)/)?.[1];
    assert.ok(command);
    const summaryPath = join(directory, 'summary.md');
    const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', command], {
      cwd: root, encoding: 'utf8', timeout: 15_000,
      env: { ...process.env, DEPLOYMENT_URL: 'https://deployment.example.com', NODE_OPTIONS: `--import=${preload}`, GITHUB_STEP_SUMMARY: summaryPath },
    });
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /FAIL.*deployment.*\/support/);
    assert.match(result.stdout, /FAIL.*production.*\/support/);
    assert.match(readFileSync(summaryPath, 'utf8'), /HTTP 500.*3 attempts/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
