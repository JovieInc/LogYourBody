#!/usr/bin/env node
// URL drift guard. Every URL literal in the repo must be registered in the
// product registry (endpoints or allowlist), and ship-affecting config
// defaults must equal the registry values. Runs in the package `test` script
// (required CI `js` job). Register new endpoints in
// packages/product-registry/src/products/logyourbody.mjs.
import { readdir, readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { basename, dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import console from 'node:console';
import process from 'node:process';
import { logYourBody } from '../src/products/logyourbody.mjs';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(packageRoot, '../..');
const { endpoints } = logYourBody;

// -- Scan exclusions ---------------------------------------------------------

const excludedDirs = new Set([
  'node_modules',
  '.git',
  '.next',
  '.turbo',
  'dist',
  'build',
  'DerivedData',
  'test_results',
  'coverage',
  'plans',
]);
const excludedFiles = new Set(['pnpm-lock.yaml', 'package-lock.json', 'yarn.lock', '.DS_Store']);
const excludedExtensions = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.icns',
  '.bin',
  '.pdf',
  '.zip',
  '.gz',
  '.tar',
  '.woff',
  '.woff2',
  '.ttf',
  '.otf',
  '.mp4',
  '.mov',
  '.a',
  '.dylib',
  '.so',
  '.jar',
  '.p12',
  '.mobileprovision',
  '.der',
  '.cer',
  '.keystore',
]);
// The guard's own patterns, the registry source (self-referential), and
// generated outputs that mirror the registry verbatim.
const excludedPaths = new Set([
  'packages/product-registry/scripts/url-drift.test.mjs',
  'packages/product-registry/src/products/logyourbody.mjs',
  'apps/web/src/lib/generated/endpoints.generated.ts',
  'apps/web/src/lib/generated/csp.generated.ts',
  'apps/ios/LogYourBody/GeneratedProductRegistry.swift',
  'docs/product/product-registry.generated.md',
]);

async function filesIn(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      if (!excludedDirs.has(entry.name)) files.push(...(await filesIn(path)));
      continue;
    }
    if (!entry.isFile()) continue;
    if (excludedFiles.has(entry.name)) continue;
    if (entry.name.startsWith('.env')) continue;
    if (excludedExtensions.has(extname(entry.name).toLowerCase())) continue;
    if (excludedPaths.has(relative(repoRoot, path))) continue;
    files.push(path);
  }
  return files;
}

// -- Registered values -------------------------------------------------------

function collectStrings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((item) => collectStrings(item, out));
  else if (value && typeof value === 'object')
    Object.values(value).forEach((item) => collectStrings(item, out));
  return out;
}

const registered = collectStrings(endpoints);
registered.push(`https://${endpoints.vendor.supabaseProjectRef}.supabase.co`);

const urlValues = []; // full scheme://... values -> exact or path-prefix match
const hostValues = []; // bare hosts -> host-suffix match
for (const value of registered) {
  if (value.includes('://')) {
    urlValues.push(value);
  } else if (/^[\w.*:-]+$/.test(value) && (value.includes('.') || value.includes(':'))) {
    hostValues.push(value.toLowerCase());
  }
}

function parseUrl(literal) {
  const match = literal.match(/^([a-z][a-z0-9+.-]*):\/\/([^/?#]+)([^?#]*)/i);
  if (!match) return null;
  const hostport = match[2].toLowerCase();
  return {
    scheme: match[1].toLowerCase(),
    hostport,
    host: hostport.replace(/:\d+$/, ''),
    path: match[3],
  };
}

function hostMatches(host, value) {
  if (value.startsWith('*.')) {
    const base = value.slice(2);
    return host === base || host.endsWith(`.${base}`);
  }
  return host === value || host.endsWith(`.${value}`);
}

function isRegistered(literal) {
  const forms = literal.endsWith('/') ? [literal, literal.slice(0, -1)] : [literal];
  for (const value of urlValues) {
    for (const form of forms) {
      if (form === value) return true;
      if (
        form.startsWith(`${value}/`) ||
        form.startsWith(`${value}?`) ||
        form.startsWith(`${value}#`)
      ) {
        return true;
      }
    }
  }
  const parsed = parseUrl(literal);
  if (parsed) {
    if (parsed.scheme === endpoints.deepLinks.scheme) return true;
    for (const value of hostValues) {
      if (hostMatches(parsed.host, value) || hostMatches(parsed.hostport, value)) return true;
    }
  }
  if (literal.startsWith('applinks:')) {
    const host = literal.slice('applinks:'.length).toLowerCase();
    for (const value of hostValues) {
      if (hostMatches(host, value)) return true;
    }
  }
  return false;
}

// Fixture-safe hosts for tests and docs placeholders.
function isFixtureSafe(literal) {
  const parsed = parseUrl(literal);
  if (!parsed) return false;
  const { host } = parsed;
  if (host.includes('*') || host.includes('[')) return true; // redacted/bracketed placeholders
  if (host.includes('your')) return true; // your-project / yourdomain doc placeholders
  if (host === 'localhost' || host === '127.0.0.1') return true;
  if (host === 'example' || host.endsWith('.example')) return true; // RFC 2606 .example TLD
  if (host === 'example.com' || host.endsWith('.example.com')) return true;
  if (host === 'bodyspec.test' || host.endsWith('.bodyspec.test')) return true;
  if (host === 'ingest.sentry.io' || host.endsWith('.ingest.sentry.io')) return true;
  if (host === 'supabase.co' || host.endsWith('.supabase.co')) {
    return /placeholder|example|local-build|test|proj/.test(host);
  }
  return false;
}

// -- Literal scan ------------------------------------------------------------

const literalPatterns = [
  /https?:\/\/[^\s"'`)>\]]+/g,
  /wss:\/\/[^\s"'`)>\]]+/g,
  /applinks:[^",\s<]+/g,
  /logyourbody:\/\/[^\s"'`)>\]]*/g,
];

function normalize(raw) {
  // Template-interpolated URLs (`https://host/${var}`, Swift `\(var)`) are
  // checked up to the interpolation point; a fully templated host has no
  // literal to check.
  const templatedTs = raw.indexOf('${');
  const templatedSwift = raw.indexOf('\\(');
  const templated =
    templatedTs === -1
      ? templatedSwift
      : templatedSwift === -1
        ? templatedTs
        : Math.min(templatedTs, templatedSwift);
  let literal = templated === -1 ? raw : raw.slice(0, templated);
  literal = literal
    .replace(/[.,;:!?]+$/, '')
    .replace(/[}\\]+$/, '')
    .replace(/\.git$/, '');
  if (/^[a-z][a-z0-9+.-]*:\/\/$/i.test(literal)) return null; // fully templated host
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(literal) && !/^applinks:[\w.-]+$/.test(literal)) {
    return null;
  }
  return literal;
}

// --staged: literal-scan only the files staged in git (pre-commit fast path).
// The consistency assertions below always run against the full repo.
const stagedOnly = process.argv.includes('--staged');

function stagedFiles() {
  const output = execFileSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACMR'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  return output
    .split('\n')
    .filter(Boolean)
    .map((path) => resolve(repoRoot, path))
    .filter((path) => {
      const name = basename(path);
      if (excludedFiles.has(name)) return false;
      if (name.startsWith('.env')) return false;
      if (excludedExtensions.has(extname(name).toLowerCase())) return false;
      if (excludedPaths.has(relative(repoRoot, path))) return false;
      return true;
    });
}

const files = stagedOnly ? stagedFiles() : await filesIn(repoRoot);
const failures = [];
let fileCount = 0;
let literalCount = 0;

for (const path of files) {
  const contents = await readFile(path, 'utf8').catch(() => null);
  if (contents === null || contents.includes('\0')) continue;
  fileCount += 1;
  const relativePath = relative(repoRoot, path);
  const lines = contents.split('\n');
  lines.forEach((line, index) => {
    for (const pattern of literalPatterns) {
      for (const match of line.matchAll(pattern)) {
        const literal = normalize(match[0]);
        if (!literal) continue;
        literalCount += 1;
        if (isRegistered(literal) || isFixtureSafe(literal)) continue;
        failures.push(
          `${relativePath}:${index + 1}: ${literal}\n  register it in packages/product-registry/src/products/logyourbody.mjs (endpoints or allowlist)`,
        );
      }
    }
  });
}

// -- Consistency assertions --------------------------------------------------
// The login-bug class: every ship-affecting default must equal the registry.

const xcconfigUrl = (value) => value.replaceAll(':/$()/', '://');

const consistencyTargets = [
  {
    file: 'apps/ios/LogYourBody/Utils/Configuration.swift',
    checks: [
      {
        name: 'API_BASE_URL default',
        pattern: /stringValue\(for: "API_BASE_URL", default: ([^)]+)\)/,
        expected: 'ProductRegistry.Hosts.api',
      },
      {
        name: 'AUTH_ISSUER default',
        pattern: /stringValue\(for: "AUTH_ISSUER", default: ([^)]+)\)/,
        expected: 'ProductRegistry.Auth.issuer',
      },
      {
        name: 'AUTH_CLIENT_ID default',
        pattern: /stringValue\(for: "AUTH_CLIENT_ID", default: ([^)]+)\)/,
        expected: 'ProductRegistry.Auth.iosClientID',
      },
      {
        name: 'AUTH_REDIRECT_URI default',
        pattern: /stringValue\(for: "AUTH_REDIRECT_URI", default: ([^)]+)\)/,
        expected: 'ProductRegistry.Auth.iosRedirectURI',
      },
    ],
  },
  // The ProductRegistry.* references above resolve through the generated Swift
  // file; pin its values to the registry so the chain stays checked end to end.
  {
    file: 'apps/ios/LogYourBody/GeneratedProductRegistry.swift',
    checks: [
      {
        name: 'Hosts.api',
        pattern: /static let api = "([^"]+)"/,
        expected: endpoints.hosts.api.url,
      },
      {
        name: 'Auth.issuer',
        pattern: /static let issuer = "([^"]+)"/,
        expected: endpoints.auth.issuer,
      },
      {
        name: 'Auth.iosClientID',
        pattern: /static let iosClientID = "([^"]+)"/,
        expected: endpoints.auth.clients.ios.id,
      },
      {
        name: 'Auth.iosRedirectURI',
        pattern: /static let iosRedirectURI = "([^"]+)"/,
        expected: endpoints.auth.clients.ios.redirectUri,
      },
    ],
  },
  {
    file: 'apps/ios/LogYourBody/Config-Production.xcconfig.template',
    normalize: xcconfigUrl,
    checks: [
      {
        name: 'API_BASE_URL',
        pattern: /^API_BASE_URL = (.+)$/m,
        expected: endpoints.hosts.api.url,
      },
      {
        name: 'API_EXPECTED_HOST',
        pattern: /^API_EXPECTED_HOST = (.+)$/m,
        expected: endpoints.hosts.api.host,
      },
      {
        name: 'AUTH_ISSUER',
        pattern: /^AUTH_ISSUER = (.+)$/m,
        expected: endpoints.auth.issuer,
      },
      {
        name: 'AUTH_CLIENT_ID',
        pattern: /^AUTH_CLIENT_ID = (.+)$/m,
        expected: endpoints.auth.clients.ios.id,
      },
      {
        name: 'AUTH_REDIRECT_URI',
        pattern: /^AUTH_REDIRECT_URI = (.+)$/m,
        expected: endpoints.auth.clients.ios.redirectUri,
      },
    ],
  },
  {
    file: 'apps/ios/Scripts/write_release_config.sh',
    checks: [
      {
        name: 'API_BASE_URL default',
        pattern: /API_BASE_URL="\$\{API_BASE_URL:-([^}]+)\}"/,
        expected: endpoints.hosts.api.url,
      },
      {
        name: 'AUTH_ISSUER default',
        pattern: /AUTH_ISSUER="\$\{AUTH_ISSUER:-([^}]+)\}"/,
        expected: endpoints.auth.issuer,
      },
      {
        name: 'AUTH_CLIENT_ID default',
        pattern: /AUTH_CLIENT_ID="\$\{AUTH_CLIENT_ID:-([^}]+)\}"/,
        expected: endpoints.auth.clients.ios.id,
      },
      {
        name: 'AUTH_REDIRECT_URI default',
        pattern: /AUTH_REDIRECT_URI="\$\{AUTH_REDIRECT_URI:-([^}]+)\}"/,
        expected: endpoints.auth.clients.ios.redirectUri,
      },
    ],
  },
  {
    file: 'apps/ios/Scripts/verify_upload_hosts.sh',
    checks: [
      {
        name: 'API_BASE_URL default',
        pattern: /API_BASE_URL="\$\{API_BASE_URL:-([^}]+)\}"/,
        expected: endpoints.hosts.api.url,
      },
    ],
  },
  {
    file: '.github/workflows/web-release-loop.yml',
    checks: [
      {
        name: 'NEXT_PUBLIC_API_URL fallback',
        pattern: /NEXT_PUBLIC_API_URL: \$\{\{ vars\.NEXT_PUBLIC_API_URL \|\| '([^']+)' \}\}/,
        expected: endpoints.hosts.api.url,
      },
    ],
  },
  {
    file: 'apps/web/src/lib/auth/jovie-oauth.ts',
    checks: [
      {
        name: 'DEFAULT_ISSUER',
        pattern: /const DEFAULT_ISSUER = ([^;]+);/,
        expected: 'endpoints.auth.issuer',
      },
      {
        name: 'DEFAULT_CLIENT_ID',
        pattern: /const DEFAULT_CLIENT_ID = ([^;]+);/,
        expected: 'endpoints.auth.clients.web.id',
      },
      {
        name: 'production redirect URI',
        pattern: /return (endpoints\.auth\.clients\.web\.redirectUri);/,
        expected: 'endpoints.auth.clients.web.redirectUri',
      },
    ],
  },
  // Same chain-pinning as iOS: the endpoints.* references above resolve
  // through the generated module, so pin its values to the registry.
  {
    file: 'apps/web/src/lib/generated/endpoints.generated.ts',
    checks: [
      {
        name: 'auth.issuer',
        pattern: /issuer: '([^']+)',/,
        expected: endpoints.auth.issuer,
      },
      {
        name: 'auth.clients.web.id',
        pattern: /web: \{\s*id: '([^']+)',/,
        expected: endpoints.auth.clients.web.id,
      },
      {
        name: 'auth.clients.web.redirectUri',
        pattern: /web: \{\s*id: '[^']+',\s*redirectUri: '([^']+)',/,
        expected: endpoints.auth.clients.web.redirectUri,
      },
    ],
  },
];

let consistencyCount = 0;
for (const target of consistencyTargets) {
  const contents = await readFile(resolve(repoRoot, target.file), 'utf8').catch(() => null);
  if (contents === null) {
    failures.push(`${target.file}: consistency target is missing`);
    continue;
  }
  const normalizeValue = target.normalize ?? ((value) => value);
  for (const { name, pattern, expected } of target.checks) {
    consistencyCount += 1;
    const match = contents.match(pattern);
    if (!match) {
      failures.push(`${target.file}: could not locate ${name}; update the guard if the code moved`);
      continue;
    }
    const actual = normalizeValue(match[1].trim());
    if (actual !== expected) {
      const line = contents.slice(0, match.index).split('\n').length;
      failures.push(
        `${target.file}:${line}: ${name} is '${actual}' but the registry says '${expected}'`,
      );
    }
  }
}

// -- Report ------------------------------------------------------------------

if (failures.length > 0) {
  console.error(
    `URL drift guard failed (${failures.length} problem${failures.length === 1 ? '' : 's'}):`,
  );
  for (const failure of failures) console.error(`  ${failure}`);
  process.exit(1);
}

console.log(
  `URL drift guard: ok — ${fileCount} files scanned, ${literalCount} URL literals registered, ${consistencyCount} consistency assertions passed`,
);
