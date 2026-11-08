import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RUBY_SCRIPT = fileURLToPath(new URL('./release-match-identifiers.rb', import.meta.url));

const PLIST_SCRIPT = `
import json, plistlib, sys
raw = sys.stdin.buffer.read()
start = raw.find(b"<?xml")
end = raw.find(b"</plist>")
if start < 0 or end < 0:
    sys.exit(2)
try:
    doc = plistlib.loads(raw[start:end + len(b"</plist>")])
except Exception:
    sys.exit(2)
if not isinstance(doc, dict):
    sys.exit(2)
payload = doc["Entitlements"] if "Entitlements" in doc else doc
if not isinstance(payload, dict):
    sys.exit(2)

def norm(value):
    if isinstance(value, bool) or isinstance(value, str):
        return value
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    raise ValueError("unsupported")

try:
    json.dump({key: norm(value) for key, value in payload.items()}, sys.stdout)
except ValueError:
    sys.exit(2)
`;

function matchingBrace(text, open) {
  let depth = 0;
  let quote = false;
  for (let index = open; index < text.length; index += 1) {
    const char = text[index];
    if (quote) {
      if (char === '\\') {
        index += 1;
        continue;
      }
      if (char === '"') quote = false;
      continue;
    }
    if (char === '"') {
      quote = true;
      continue;
    }
    if (char === '{') depth += 1;
    else if (char === '}') {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  throw new Error('project file unreadable');
}

export function releaseTargetsFromProject(text) {
  const targets = [];
  let cursor = 0;
  while (cursor < text.length) {
    const marker = text.indexOf('isa = XCBuildConfiguration;', cursor);
    if (marker < 0) break;
    const open = text.lastIndexOf('{', marker);
    if (open < 0) break;
    const close = matchingBrace(text, open);
    const block = text.slice(open, close + 1);
    cursor = close + 1;
    if (!/\bname = Release;/.test(block)) continue;
    const bundle = block.match(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/);
    if (!bundle) continue;
    const entitlements = block.match(/CODE_SIGN_ENTITLEMENTS = "?([^";]+)"?;/);
    const bundleId = bundle[1].trim();
    const entitlementsPath = entitlements ? entitlements[1].trim() : '';
    if (!bundleId || bundleId.includes('$(')) continue;
    targets.push({ bundleId, entitlementsPath });
  }
  return targets;
}

function iosPath(root, relativePath) {
  if (!relativePath || relativePath.includes('..') || path.isAbsolute(relativePath)) return '';
  const full = path.resolve(root, 'apps/ios', relativePath);
  const base = path.resolve(root, 'apps/ios');
  if (full !== base && !full.startsWith(`${base}${path.sep}`)) return '';
  return full;
}

export function parseEntitlements(buffer) {
  const result = spawnSync('python3', ['-c', PLIST_SCRIPT], {
    input: buffer,
    encoding: 'utf8',
    timeout: 10_000,
  });
  if (result.status !== 0 || !result.stdout) return null;
  try {
    const parsed = JSON.parse(result.stdout);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function loadReleaseEntitlements(root, bundleIds, projectText) {
  const text = projectText ?? readFileSync(path.join(root, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'), 'utf8');
  const pathsById = new Map();
  for (const target of releaseTargetsFromProject(text)) {
    const paths = pathsById.get(target.bundleId) || [];
    if (target.entitlementsPath) paths.push(target.entitlementsPath);
    pathsById.set(target.bundleId, paths);
  }
  const entitlementsByBundleId = {};
  for (const bundleId of bundleIds) {
    const merged = {};
    for (const relativePath of pathsById.get(bundleId) || []) {
      const full = iosPath(root, relativePath);
      if (!full) return null;
      let parsed;
      try {
        parsed = parseEntitlements(readFileSync(full));
      } catch {
        return null;
      }
      if (!parsed) return null;
      for (const [key, value] of Object.entries(parsed)) {
        if (Array.isArray(value) && Array.isArray(merged[key])) {
          merged[key] = [...new Set([...merged[key], ...value])];
        } else if (merged[key] !== true) {
          merged[key] = value;
        }
      }
    }
    entitlementsByBundleId[bundleId] = merged;
  }
  return entitlementsByBundleId;
}

export function releaseBundleIds(releaseFile, ruby = 'ruby') {
  const result = spawnSync(ruby, [RUBY_SCRIPT, releaseFile], {
    encoding: 'utf8',
    timeout: 20_000,
    env: {
      PATH: process.env.PATH || '',
      HOME: process.env.HOME || '',
      LANG: 'C',
      LC_ALL: 'C',
    },
  });
  if (result.status !== 0) throw new Error('release signing identifiers unreadable');
  let ids;
  try {
    ids = JSON.parse(result.stdout);
  } catch {
    throw new Error('release signing identifiers unreadable');
  }
  if (!Array.isArray(ids) || ids.length === 0 || ids.some((id) => typeof id !== 'string' || !id.trim())) {
    throw new Error('release signing identifiers unreadable');
  }
  return ids;
}
