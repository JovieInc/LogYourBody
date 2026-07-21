#!/usr/bin/env node

// Token drift guard: compares the canonical token JSON (tokens/**) against the
// iOS (Theme.swift + Color+Theme.swift) and web (tailwind.config.ts +
// globals.css) token layers, and enforces a ratchet baseline so drift can only
// go down. The computed drift set must exactly match drift-baseline.json:
// new drift fails ("drift increased"), fixed drift fails ("baseline stale").
// Re-run with --update to regenerate the baseline.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(packageRoot, '..', '..');

const tokensDir = path.join(packageRoot, 'tokens');
const mapPath = path.join(packageRoot, 'token-map.json');
const baselinePath = path.join(packageRoot, 'drift-baseline.json');

const updateMode = process.argv.includes('--update');

// ---------------------------------------------------------------------------
// Canonical tokens
// ---------------------------------------------------------------------------

function normalizeHex(hex) {
  let value = hex.trim().toLowerCase();
  if (!value.startsWith('#')) return value;
  value = value.slice(1);
  if (value.length === 3) {
    value = value
      .split('')
      .map((char) => char + char)
      .join('');
  }
  if (value.length === 8) {
    value = value.slice(0, 6);
  }
  return `#${value}`;
}

function normalizeValue(value) {
  if (typeof value === 'number') return value;
  if (typeof value !== 'string') return value;
  if (/^#[0-9a-fA-F]{3,8}$/.test(value.trim())) return normalizeHex(value);
  if (/^-?\d+(?:\.\d+)?$/.test(value.trim())) return Number(value.trim());
  return value;
}

function walkJsonFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkJsonFiles(full));
    } else if (entry.isFile() && entry.name.endsWith('.json')) {
      files.push(full);
    }
  }
  return files.sort();
}

function flattenTokenTree(node, prefix, out) {
  for (const [key, child] of Object.entries(node)) {
    if (child && typeof child === 'object' && 'value' in child) {
      out[prefix ? `${prefix}.${key}` : key] = child.value;
    } else if (child && typeof child === 'object') {
      flattenTokenTree(child, prefix ? `${prefix}.${key}` : key, out);
    }
  }
}

function loadCanonicalTokens() {
  const raw = {};
  for (const file of walkJsonFiles(tokensDir)) {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    flattenTokenTree(parsed, '', raw);
  }

  const resolved = {};
  const resolving = new Set();

  function resolveToken(tokenPath) {
    if (tokenPath in resolved) return resolved[tokenPath];
    if (!(tokenPath in raw)) {
      throw new Error(`Unresolved token reference: {${tokenPath}}`);
    }
    if (resolving.has(tokenPath)) {
      throw new Error(`Circular token reference: {${tokenPath}}`);
    }
    resolving.add(tokenPath);
    let value = raw[tokenPath];
    if (typeof value === 'string') {
      const refMatch = value.match(/^\{(.+)\}$/);
      if (refMatch) {
        value = resolveToken(refMatch[1]);
      }
    }
    resolving.delete(tokenPath);
    resolved[tokenPath] = normalizeValue(value);
    return resolved[tokenPath];
  }

  for (const tokenPath of Object.keys(raw)) {
    resolveToken(tokenPath);
  }
  return resolved;
}

// ---------------------------------------------------------------------------
// iOS extraction (Theme.swift + Color+Theme.swift)
// ---------------------------------------------------------------------------

function extractBlock(content, headerPattern) {
  const start = content.search(headerPattern);
  if (start === -1) return null;
  const braceStart = content.indexOf('{', start);
  let depth = 0;
  for (let index = braceStart; index < content.length; index += 1) {
    if (content[index] === '{') depth += 1;
    if (content[index] === '}') {
      depth -= 1;
      if (depth === 0) return content.slice(braceStart + 1, index);
    }
  }
  return null;
}

function loadIosTokens() {
  const themePath = path.join(repoRoot, 'apps/ios/LogYourBody/DesignSystem/Theme.swift');
  const colorExtPath = path.join(repoRoot, 'apps/ios/LogYourBody/Extensions/Color+Theme.swift');
  const theme = fs.readFileSync(themePath, 'utf8');
  const colorExt = fs.readFileSync(colorExtPath, 'utf8');

  // Named colors from Color+Theme.swift (e.g. .jovieAction, .jovieHairline)
  const namedColors = { white: '#ffffff', black: '#000000' };
  for (const match of colorExt.matchAll(
    /static let (\w+) = Color\(hex: "#([0-9a-fA-F]{3,8})"\)/g,
  )) {
    namedColors[match[1]] = normalizeHex(`#${match[2]}`);
  }
  for (const match of colorExt.matchAll(/static let (\w+) = Color\.(white|black)\b/g)) {
    namedColors[match[1]] = namedColors[match[2]];
  }

  // JovieTokens geometry constants (screenInset, cardRadius, controlRadius, ...)
  const jovieTokens = {};
  const jovieBlock = extractBlock(theme, /enum JovieTokens/);
  if (jovieBlock) {
    for (const match of jovieBlock.matchAll(
      /static let (\w+): (?:CGFloat|Double) = (-?\d+(?:\.\d+)?)/g,
    )) {
      jovieTokens[match[1]] = Number(match[2]);
    }
  }

  function parseNumericBlock(block) {
    const values = {};
    if (!block) return values;
    for (const match of block.matchAll(/let (\w+): CGFloat = ([^\n]+)/g)) {
      const expr = match[2].trim();
      const literal = expr.match(/^(-?\d+(?:\.\d+)?)$/);
      const jovieRef = expr.match(/^JovieTokens\.(\w+)$/);
      if (literal) {
        values[match[1]] = Number(literal[1]);
      } else if (jovieRef && jovieRef[1] in jovieTokens) {
        values[match[1]] = jovieTokens[jovieRef[1]];
      }
    }
    return values;
  }

  const spacing = parseNumericBlock(extractBlock(theme, /struct SpacingTheme/));
  const radius = parseNumericBlock(extractBlock(theme, /struct RadiusTheme/));

  // Colors from the DefaultTheme ColorTheme(...) initializer
  const colors = {};
  const colorsStart = theme.indexOf('let colors = ColorTheme(');
  const colorsEnd = colorsStart === -1 ? -1 : theme.indexOf('\n    )', colorsStart);
  const colorsBlock = colorsStart === -1 || colorsEnd === -1 ? null : theme.slice(colorsStart, colorsEnd);
  if (colorsBlock) {
    for (const match of colorsBlock.matchAll(
      /(\w+): Color\(hex: "#([0-9a-fA-F]{3,8})"\)/g,
    )) {
      colors[match[1]] = normalizeHex(`#${match[2]}`);
    }
    for (const match of colorsBlock.matchAll(/(\w+): \.(\w+)(?:\.opacity\([\d.]+\))?,/g)) {
      if (!(match[1] in colors) && match[2] in namedColors) {
        colors[match[1]] = namedColors[match[2]];
      }
    }
  }

  return { colors, spacing, radius };
}

// ---------------------------------------------------------------------------
// Web extraction (tailwind.config.ts + globals.css)
// ---------------------------------------------------------------------------

function hslToHex(h, s, l) {
  const saturation = s / 100;
  const lightness = l / 100;
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const huePrime = (((h % 360) + 360) % 360) / 60;
  const x = chroma * (1 - Math.abs((huePrime % 2) - 1));
  let rgb;
  if (huePrime < 1) rgb = [chroma, x, 0];
  else if (huePrime < 2) rgb = [x, chroma, 0];
  else if (huePrime < 3) rgb = [0, chroma, x];
  else if (huePrime < 4) rgb = [0, x, chroma];
  else if (huePrime < 5) rgb = [x, 0, chroma];
  else rgb = [chroma, 0, x];
  const m = lightness - chroma / 2;
  const toHex = (channel) =>
    Math.round((channel + m) * 255)
      .toString(16)
      .padStart(2, '0');
  return `#${toHex(rgb[0])}${toHex(rgb[1])}${toHex(rgb[2])}`;
}

function loadWebTokens() {
  const tailwindPath = path.join(repoRoot, 'apps/web/tailwind.config.ts');
  const globalsPath = path.join(repoRoot, 'apps/web/src/app/globals.css');
  const tailwind = fs.readFileSync(tailwindPath, 'utf8');
  const globals = fs.readFileSync(globalsPath, 'utf8');

  // Tailwind hex literals keyed by color name
  const tailwindColors = {};
  for (const match of tailwind.matchAll(/'([\w-]+)':\s*'#([0-9a-fA-F]{3,8})'/g)) {
    tailwindColors[match[1]] = normalizeHex(`#${match[2]}`);
  }

  // CSS vars from the first :root block (dark mode is the default theme)
  const rootBlock = extractBlock(globals, /:root/);
  const cssVars = {};
  if (rootBlock) {
    for (const match of rootBlock.matchAll(
      /--([\w-]+):\s*(-?[\d.]+)\s+([\d.]+)%\s+([\d.]+)%/g,
    )) {
      cssVars[match[1]] = hslToHex(Number(match[2]), Number(match[3]), Number(match[4]));
    }
    for (const match of rootBlock.matchAll(/--([\w-]+):\s*(-?[\d.]+)px/g)) {
      cssVars[match[1]] = Number(match[2]);
    }
  }

  return { tailwindColors, cssVars };
}

// ---------------------------------------------------------------------------
// Comparison + baseline
// ---------------------------------------------------------------------------

function lookupIos(ios, target) {
  const [group, key] = target.split('.');
  return ios[group]?.[key];
}

function lookupWeb(web, target) {
  if (target.startsWith('tailwind:')) {
    return web.tailwindColors[target.slice('tailwind:'.length)];
  }
  if (target.startsWith('--')) {
    return web.cssVars[target.slice(2)];
  }
  return undefined;
}

function formatValue(value) {
  return value === undefined ? null : value;
}

function computeDrift(canonical, ios, web, map) {
  const drift = [];
  let comparisons = 0;

  for (const [tokenPath, targets] of Object.entries(map)) {
    if (!(tokenPath in canonical)) {
      throw new Error(`token-map.json references unknown canonical token: ${tokenPath}`);
    }
    const canonicalValue = canonical[tokenPath];

    const checks = [];
    if (targets.ios) checks.push({ platform: 'ios', target: targets.ios, actual: lookupIos(ios, targets.ios) });
    for (const webTarget of targets.web ?? []) {
      checks.push({ platform: 'web', target: webTarget, actual: lookupWeb(web, webTarget) });
    }

    for (const check of checks) {
      comparisons += 1;
      if (check.actual !== canonicalValue) {
        drift.push({
          token: tokenPath,
          platform: check.platform,
          target: check.target,
          canonical: formatValue(canonicalValue),
          actual: formatValue(check.actual),
        });
      }
    }
  }

  drift.sort((a, b) =>
    `${a.token}|${a.platform}|${a.target}`.localeCompare(`${b.token}|${b.platform}|${b.target}`),
  );
  return { drift, comparisons };
}

function driftKey(entry) {
  return `${entry.token}|${entry.platform}|${entry.target}`;
}

function formatDriftEntry(entry) {
  return `  - [${entry.platform}] ${entry.token} (${entry.target}): canonical=${entry.canonical} actual=${entry.actual}`;
}

function main() {
  const canonical = loadCanonicalTokens();
  const ios = loadIosTokens();
  const web = loadWebTokens();
  const { map } = JSON.parse(fs.readFileSync(mapPath, 'utf8'));

  const { drift, comparisons } = computeDrift(canonical, ios, web, map);
  const mappedTokens = Object.keys(map).length;

  if (updateMode) {
    const baseline = { version: 1, drift };
    fs.writeFileSync(baselinePath, `${JSON.stringify(baseline, null, 2)}\n`);
    console.log(
      `Token drift guard: baseline updated — ${mappedTokens} mapped tokens, ${comparisons} comparisons, ${drift.length} known drifts recorded`,
    );
    return;
  }

  if (!fs.existsSync(baselinePath)) {
    console.error('Token drift guard: drift-baseline.json missing. Run with --update to create it.');
    process.exit(1);
  }

  const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
  const baselineByKey = new Map((baseline.drift ?? []).map((entry) => [driftKey(entry), entry]));
  const computedByKey = new Map(drift.map((entry) => [driftKey(entry), entry]));

  const newDrift = drift.filter((entry) => !baselineByKey.has(driftKey(entry)));
  const fixedDrift = (baseline.drift ?? []).filter((entry) => !computedByKey.has(driftKey(entry)));

  if (newDrift.length === 0 && fixedDrift.length === 0) {
    console.log(
      `Token drift guard: ok — ${mappedTokens} mapped tokens, ${drift.length} known drifts (baseline)`,
    );
    return;
  }

  if (newDrift.length > 0) {
    console.error('\nToken drift guard: drift increased. New mismatches not in the baseline:');
    for (const entry of newDrift) {
      console.error(formatDriftEntry(entry));
    }
    console.error('Fix the platform value to match the canonical token, or update the mapping.');
  }
  if (fixedDrift.length > 0) {
    console.error('\nToken drift guard: baseline stale. These baseline drifts are now fixed:');
    for (const entry of fixedDrift) {
      console.error(formatDriftEntry(entry));
    }
    console.error('Re-run with --update to shrink the baseline.');
  }
  process.exit(1);
}

main();
