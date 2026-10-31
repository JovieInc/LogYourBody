#!/usr/bin/env node
// LYB-272. Compare native and web product surfaces with the vendored Jovie
// launch-contract fixture (JovieInc/Jovie scripts/fixtures/lyb-launch-contract.json,
// lyb-launch-contract/v1). An unlisted surface fails. A listed hide or delete
// surface fails while it is still routable. Launch and repair rows are allowed.
// Redirect-only web tombstones and unmounted hide/delete screens are not routes.
//
// Pre-existing violations are an exact baseline. CI also passes the merge base:
// a new surface id cannot be silenced by editing that baseline. Removing a
// violation requires shrinking the baseline in the same change. The baseline
// does not classify new surfaces; classification requires an explicit declaration.
// New static web routes use reviewed web-surface-additions.json declarations.
// These extend the local inventory without rewriting the pinned upstream contract.

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import process from 'node:process';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = join(SCRIPT_DIR, '..');
export const INVENTORY_PATH = join(SCRIPT_DIR, 'fixtures', 'lyb-launch-contract.json');
export const WEB_ADDITIONS_PATH = join(SCRIPT_DIR, 'fixtures', 'web-surface-additions.json');
export const BASELINE_PATH = join(SCRIPT_DIR, 'fixtures', 'surface-reconciliation-baseline.json');
export const BASELINE_SCHEMA = 'lyb.surface-reconciliation-baseline/v1';
export const DISPOSITIONS = new Set(['launch', 'repair', 'hide', 'delete']);

// Named surfaces that are not WorldClassScreen or PaidAppSurface cases.
const EXTRA_SURFACES = [
  ['ios.sheet.dexaImport', 'DexaPDFImportSheet'],
  ['ios.sheet.trainingLiveSession', 'TrainingLiveSessionView'],
  ['ios.sheet.voiceSetReview', 'VoiceSetReviewView'],
  ['ios.prototype.composerLoggingSelector', 'ComposerLoggingSelectorState'],
];

const PAGE_FILE = /^page\.(?:tsx|ts|jsx|js)$/u;

function posix(path) {
  return path.split(sep).join('/');
}

function walk(dir, files) {
  if (!existsSync(dir)) return files;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) continue;
    if (entry.name === 'node_modules' || entry.name === '__tests__') continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

export function stripComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/[^\n]*/g, '$1');
}

// Drop #if DEBUG bodies. The #else branch of a DEBUG condition is kept.
export function stripDebug(source) {
  const lines = source.split('\n');
  const out = [];
  const stack = [];
  let skipping = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (/^#if\b/u.test(trimmed)) {
      const debug = /^#if\s+DEBUG\b/u.test(trimmed);
      stack.push({ debug, elseKept: false });
      skipping = stack.some((frame) => frame.debug && !frame.elseKept);
      continue;
    }
    if (/^#elseif\b/u.test(trimmed) || /^#else\b/u.test(trimmed)) {
      const frame = stack.at(-1);
      if (frame?.debug && /^#else\b/u.test(trimmed)) frame.elseKept = true;
      else if (frame?.debug) frame.elseKept = false;
      skipping = stack.some((item) => item.debug && !item.elseKept);
      continue;
    }
    if (/^#endif\b/u.test(trimmed)) {
      stack.pop();
      skipping = stack.some((frame) => frame.debug && !frame.elseKept);
      continue;
    }
    if (!skipping) out.push(line);
  }
  return out.join('\n');
}

function enumCases(source, name) {
  const uncommented = stripComments(source);
  const body = uncommented.match(new RegExp(String.raw`enum\s+${name}\b[^{]*\{([\s\S]*?)^\}`, 'm'))?.[1];
  if (!body) throw new Error(`Missing native registry: ${name}`);
  const cases = [];
  let depth = 0;
  for (const line of body.split('\n')) {
    const declaration = depth === 0 ? line.match(/^\s*case\s+(.+)$/u) : null;
    if (declaration) {
      for (const entry of declaration[1].split(',')) {
        const value = entry.trim().match(/^(\w+)(?:\s*=\s*"([^"]+)")?$/u);
        if (!value) throw new Error(`Unsupported native registry case: ${name}.${entry.trim()}`);
        cases.push(value[2] ?? value[1]);
      }
    }
    const code = line.replace(/"(?:\\.|[^"\\])*"/g, '');
    depth += (code.match(/\{/g)?.length ?? 0) - (code.match(/\}/g)?.length ?? 0);
  }
  if (depth !== 0 || !cases.length || new Set(cases).size !== cases.length) {
    throw new Error(`Empty or duplicate native registry: ${name}`);
  }
  return cases;
}

function readText(path) {
  return readFileSync(path, 'utf8');
}

function relativePath(root, path) {
  return posix(relative(root, path));
}

function record(map, id, path, reachable) {
  const current = map.get(id);
  if (!current) {
    map.set(id, { id, path, reachable });
    return;
  }
  if (reachable && !current.reachable) {
    current.reachable = true;
    current.path = path;
  } else if (reachable === current.reachable && path < current.path) {
    current.path = path;
  }
}

function webRoute(relativeFile) {
  const parts = relativeFile
    .split('/')
    .slice(0, -1)
    .filter((part) => part && !part.startsWith('(') && !part.startsWith('@') && !part.startsWith('_'));
  return `web:/${parts.join('/')}`;
}

function isRedirectOnly(source) {
  const code = stripComments(source);
  if (!/\b(?:redirect|permanentRedirect)\s*\(/u.test(code)) return false;
  return !/<[A-Za-z]/u.test(code);
}

function modeRouted(source, caseName) {
  const withoutLabels = stripDebug(stripComments(source)).replace(
    new RegExp(String.raw`\bcase\s+\.${caseName}\b`, 'g'),
    '',
  );
  return new RegExp(String.raw`(^|[=(\s])\.${caseName}\b`, 'm').test(withoutLabels);
}

function screenMounted(source, caseName) {
  const code = stripComments(source);
  return (
    new RegExp(String.raw`worldClassScreen\(\s*\.${caseName}\b`).test(code) ||
    new RegExp(String.raw`\bscreen\s*:\s*\.${caseName}\b`).test(code) ||
    new RegExp(String.raw`\bWorldClassScreen\.${caseName}\b`).test(code)
  );
}

function symbolRouted(source, symbol) {
  const code = stripComments(source).replace(new RegExp(String.raw`\b(?:struct|enum|class)\s+${symbol}\b`), '');
  return new RegExp(String.raw`\b${symbol}\b`).test(code);
}

function screenStructs(source) {
  const names = [];
  // Generic shells such as SettingsDetailScreen<Content> are components.
  // Loading variants are part of the screen that presents them.
  for (const match of stripComments(source).matchAll(
    /\bstruct\s+([A-Z][A-Za-z0-9]*Screen)\b([^{]*)\{/g,
  )) {
    if (match[1].endsWith('LoadingScreen') || match[2].includes('<')) continue;
    names.push(match[1]);
  }
  return names;
}

export function enumerateSurfaces(root) {
  const iosRoot = join(root, 'apps', 'ios', 'LogYourBody');
  const webRoot = join(root, 'apps', 'web', 'src', 'app');
  if (!existsSync(iosRoot) && !existsSync(webRoot)) {
    throw new Error('Expected apps/ios/LogYourBody or apps/web/src/app');
  }
  const surfaces = new Map();
  const swiftSources = walk(iosRoot, [])
    .filter((path) => path.endsWith('.swift'))
    .map((file) => ({ rel: relativePath(root, file), source: readText(file) }))
    .sort((a, b) => a.rel.localeCompare(b.rel));

  const theme = swiftSources.find((file) => file.rel === 'apps/ios/LogYourBody/DesignSystem/Theme.swift');
  const screenCases = theme ? enumCases(theme.source, 'WorldClassScreen') : [];
  if (theme) {
    for (const caseName of screenCases) {
      record(surfaces, `ios.screen.${caseName}`, theme.rel, false);
    }
  }

  const policy = swiftSources.find(
    (file) => file.rel === 'apps/ios/LogYourBody/Views/MainTabViewPolicies.swift',
  );
  const modes = policy ? enumCases(policy.source, 'PaidAppSurface') : [];
  if (policy) {
    for (const caseName of modes) record(surfaces, `ios.mode.${caseName}`, policy.rel, false);
  }

  for (const file of swiftSources) {
    if (file !== theme) {
      for (const caseName of screenCases) {
        if (screenMounted(file.source, caseName)) {
          record(surfaces, `ios.screen.${caseName}`, file.rel, true);
        }
      }
    }
    for (const caseName of modes) {
      if (modeRouted(file.source, caseName)) record(surfaces, `ios.mode.${caseName}`, file.rel, true);
    }
    for (const name of screenStructs(file.source)) {
      record(surfaces, `ios.view.${name}`, file.rel, true);
    }
  }

  for (const [id, symbol] of EXTRA_SURFACES) {
    const hits = swiftSources.filter((file) => symbolRouted(file.source, symbol));
    if (!hits.length) continue;
    record(surfaces, id, hits[0].rel, true);
  }

  for (const file of walk(webRoot, [])) {
    if (!PAGE_FILE.test(file.split(sep).at(-1))) continue;
    const rel = relativePath(root, file);
    const routeFile = rel.slice('apps/web/src/app/'.length);
    const reachable = !isRedirectOnly(readText(file));
    record(surfaces, webRoute(routeFile), rel, reachable);
  }

  return [...surfaces.values()].sort((a, b) => a.id.localeCompare(b.id));
}

export function loadInventory(path, additionsPath = null) {
  const bytes = readFileSync(path);
  const inventory = JSON.parse(bytes.toString('utf8'));
  if (inventory?.schema !== 'lyb-launch-contract/v1' || !inventory.surfaces) {
    throw new Error('Invalid launch-contract fixture');
  }
  for (const [id, disposition] of Object.entries(inventory.surfaces)) {
    if (typeof id !== 'string' || !id || !DISPOSITIONS.has(disposition)) {
      throw new Error(`Invalid surface disposition: ${id}`);
    }
  }
  if (additionsPath) {
    const additions = JSON.parse(readText(additionsPath));
    if (
      additions?.schema !== 'lyb.web-surface-additions/v1' ||
      !additions.surfaces ||
      typeof additions.surfaces !== 'object' ||
      Array.isArray(additions.surfaces)
    )
      throw new Error('Invalid local web surface declarations');
    for (const [id, disposition] of Object.entries(additions.surfaces)) {
      // Local web declarations cannot override any pinned disposition or add native surfaces.
      if (
        !/^web:\/(?:[a-z0-9-]+\/)*[a-z0-9-]+$/u.test(id) ||
        !DISPOSITIONS.has(disposition) ||
        Object.hasOwn(inventory.surfaces, id)
      )
        throw new Error(`Invalid local web surface declaration: ${id}`);
      inventory.surfaces[id] = disposition;
    }
  }
  return {
    inventory,
    digest: createHash('sha256').update(bytes).digest('hex'),
  };
}

export function findingsFor(surfaces, inventory) {
  const findings = [];
  for (const surface of surfaces) {
    const disposition = inventory.surfaces[surface.id];
    if (disposition === undefined) {
      findings.push({
        kind: 'unlisted',
        disposition: null,
        id: surface.id,
        path: surface.path,
      });
      continue;
    }
    if ((disposition === 'hide' || disposition === 'delete') && surface.reachable) {
      findings.push({
        kind: disposition === 'hide' ? 'hidden-reachable' : 'deleted-reachable',
        disposition,
        id: surface.id,
        path: surface.path,
      });
    }
  }
  return findings.sort((a, b) => a.id.localeCompare(b.id) || a.path.localeCompare(b.path));
}

function sameFinding(a, b) {
  return (
    a?.kind === b?.kind &&
    a?.disposition === b?.disposition &&
    a?.id === b?.id &&
    a?.path === b?.path
  );
}

export function assess({ findings, baseline, baseFindings = null }) {
  const head = new Map((baseline ?? []).map((finding) => [finding.id, finding]));
  const baseIds = baseFindings ? new Set(baseFindings.map((finding) => finding.id)) : null;
  const rows = [];
  for (const finding of findings) {
    const recorded = head.get(finding.id);
    const grown = baseIds !== null && !baseIds.has(finding.id);
    const stale = baseline !== null && !sameFinding(recorded, finding);
    let result = 'known';
    if (baseline === null || grown || stale) result = 'FAIL';
    rows.push({ ...finding, result });
  }
  if (baseline !== null) {
    for (const recorded of baseline) {
      if (!findings.some((finding) => finding.id === recorded.id)) {
        rows.push({ ...recorded, result: 'resolved' });
      }
    }
  }
  rows.sort((a, b) => {
    const order = { FAIL: 0, resolved: 1, known: 2 };
    return order[a.result] - order[b.result] || a.id.localeCompare(b.id);
  });
  const summary = {
    fail: rows.filter((row) => row.result === 'FAIL').length,
    resolved: rows.filter((row) => row.result === 'resolved').length,
    known: rows.filter((row) => row.result === 'known').length,
  };
  return { ok: summary.fail === 0 && summary.resolved === 0, rows, summary };
}

export function formatReport(summary, rows) {
  const status = summary.fail || summary.resolved ? 'fail' : 'pass';
  const lines = [
    `surface reconciliation: ${status} — new ${summary.fail}, resolved ${summary.resolved}, known ${summary.known}`,
  ];
  const header = ['result', 'kind', 'disposition', 'surface', 'path'];
  const body = rows.map((row) => [
    row.result,
    row.kind,
    row.disposition ?? '',
    row.id,
    row.path,
  ]);
  const widths = header.map((name, index) =>
    Math.max(name.length, ...body.map((columns) => columns[index].length)),
  );
  const render = (columns) => columns.map((value, index) => value.padEnd(widths[index])).join('  ');
  lines.push(render(header));
  lines.push(widths.map((width) => '-'.repeat(width)).join('  '));
  for (const columns of body) lines.push(render(columns));
  if (!body.length) lines.push('(no drift)');
  return `${lines.join('\n')}\n`;
}

export function parseBaseline(text) {
  const value = JSON.parse(text);
  if (value?.schema !== BASELINE_SCHEMA || !Array.isArray(value.findings)) {
    throw new Error('Invalid surface reconciliation baseline');
  }
  if (typeof value.inventoryDigest !== 'string' || !/^[0-9a-f]{64}$/u.test(value.inventoryDigest)) {
    throw new Error('Baseline is missing the launch-contract digest');
  }
  for (const finding of value.findings) {
    if (
      !finding ||
      !['unlisted', 'hidden-reachable', 'deleted-reachable'].includes(finding.kind) ||
      (finding.disposition !== null && !DISPOSITIONS.has(finding.disposition)) ||
      typeof finding.id !== 'string' ||
      !finding.id ||
      typeof finding.path !== 'string' ||
      !finding.path ||
      finding.path.includes('\\') ||
      finding.path.startsWith('/')
    ) {
      throw new Error('Invalid baseline finding');
    }
  }
  return value;
}

function gitHas(root, spec) {
  try {
    execFileSync('git', ['cat-file', '-e', spec], { cwd: root, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

export function baseFindings(root, ref) {
  if (!gitHas(root, ref)) throw new Error(`base ref not available: ${ref}`);
  const spec = `${ref}:scripts/fixtures/surface-reconciliation-baseline.json`;
  if (!gitHas(root, spec)) return null;
  return parseBaseline(execFileSync('git', ['show', spec], { cwd: root, encoding: 'utf8' })).findings;
}

function printUsage() {
  return 'usage: node scripts/surface-reconciliation.mjs [--root dir] [--inventory file] [--baseline file|--no-baseline] [--base-ref sha]';
}

function optionValue(argv, index) {
  const value = argv[index];
  if (!value || value.startsWith('--')) throw new Error(printUsage());
  return value;
}

export function runCli(argv, stdout = process.stdout) {
  const options = {
    root: REPO_ROOT,
    inventory: INVENTORY_PATH,
    baseline: BASELINE_PATH,
    baseRef: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--no-baseline') options.baseline = null;
    else if (arg === '--root') options.root = optionValue(argv, ++index);
    else if (arg === '--inventory') options.inventory = optionValue(argv, ++index);
    else if (arg === '--baseline') options.baseline = optionValue(argv, ++index);
    else if (arg === '--base-ref') options.baseRef = optionValue(argv, ++index);
    else throw new Error(printUsage());
  }
  const additionsPath = join(options.root, 'scripts', 'fixtures', 'web-surface-additions.json');
  const { inventory, digest } = loadInventory(
    options.inventory,
    existsSync(additionsPath) ? additionsPath : null,
  );
  const findings = findingsFor(enumerateSurfaces(options.root), inventory);
  let baseline = null;
  if (options.baseline) {
    const parsed = parseBaseline(readText(options.baseline));
    if (parsed.inventoryDigest !== digest) {
      throw new Error('Launch-contract digest changed; review the baseline against the fixture');
    }
    baseline = parsed.findings;
  }
  const base = options.baseRef ? baseFindings(options.root, options.baseRef) : null;
  const { ok, rows, summary } = assess({ findings, baseline, baseFindings: base });
  stdout.write(formatReport(summary, rows));
  return ok ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    process.exitCode = runCli(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 2;
  }
}
