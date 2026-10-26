import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const IDENTIFIER = 'HKMetadataKeySyncIdentifier';
const VERSION = 'HKMetadataKeySyncVersion';
const VERSION_ENTRY = 'HKMetadataKeySyncVersion: NSNumber(value: 1)';
const CAST = ' as [String: Any]';

// reject HKMetadataKeySyncIdentifier without HKMetadataKeySyncVersion
function isIdentChar(char) {
  return Boolean(char && /[A-Za-z0-9_]/u.test(char));
}

function skipString(source, index) {
  if (source.startsWith('"""', index)) {
    const end = source.indexOf('"""', index + 3);
    return end < 0 ? source.length : end + 3;
  }
  let cursor = index + 1;
  while (cursor < source.length) {
    if (source[cursor] === '\\') {
      cursor += 2;
      continue;
    }
    if (source[cursor] === '"') return cursor + 1;
    if (source[cursor] === '\n') return cursor;
    cursor += 1;
  }
  return cursor;
}

function followedByColon(source, index) {
  let cursor = index;
  while (cursor < source.length && /[ \t\r\n]/u.test(source[cursor])) cursor += 1;
  return source[cursor] === ':';
}

function tokenAt(source, index, token) {
  return (
    source.startsWith(token, index) &&
    !isIdentChar(source[index - 1]) &&
    !isIdentChar(source[index + token.length]) &&
    followedByColon(source, index + token.length)
  );
}

export function analyze(path, source) {
  const findings = [];
  // Full-tree ratchet scans import this for every Swift file. Skip the character
  // walk unless the file can name a sync identifier; that walk was enough to push
  // the coverage wrapper past Vitest's default timeout.
  if (!source.includes(IDENTIFIER)) return findings;
  const stack = [];
  let index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      const end = source.indexOf('\n', index);
      index = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', index)) {
      const end = source.indexOf('*/', index + 2);
      index = end < 0 ? source.length : end + 2;
      continue;
    }
    if (source[index] === '"') {
      index = skipString(source, index);
      continue;
    }
    if (source[index] === '[') {
      stack.push({ start: index, identifier: false, version: false });
      index += 1;
      continue;
    }
    if (source[index] === ']') {
      const frame = stack.pop();
      if (frame?.identifier && !frame.version) {
        const body = source
          .slice(frame.start, index + 1)
          .replace(/\s+/gu, ' ')
          .trim();
        findings.push({
          path,
          key: `missing HKMetadataKeySyncVersion beside HKMetadataKeySyncIdentifier: ${body}`,
          start: frame.start,
          end: index + 1,
        });
      }
      index += 1;
      continue;
    }
    if (stack.length && tokenAt(source, index, IDENTIFIER)) {
      stack.at(-1).identifier = true;
      index += IDENTIFIER.length;
      continue;
    }
    if (stack.length && tokenAt(source, index, VERSION)) {
      stack.at(-1).version = true;
      index += VERSION.length;
      continue;
    }
    index += 1;
  }
  return findings;
}

export function scan({ files, readSource }) {
  return files
    .filter((path) => path.endsWith('.swift'))
    .flatMap((path) =>
      analyze(path, readSource(path)).map(({ path: findingPath, key }) => ({
        path: findingPath,
        key,
      })),
    );
}

function repairSpan(source, start, end) {
  const interior = source.slice(start + 1, end - 1);
  const trimmed = interior.trimEnd();
  const trailing = interior.slice(trimmed.length);
  const comma = trimmed.length > 0 && !trimmed.endsWith(',') ? ',' : '';
  const literal = `[${trimmed}${comma} ${VERSION_ENTRY}${trailing}]`;
  const rest = source.slice(end);
  const cast = /^\s*as\s+\[String:\s*Any\]/u.test(rest) ? '' : CAST;
  return `${source.slice(0, start)}${literal}${cast}${rest}`;
}

export function repairSource(source) {
  return analyze('repair.swift', source)
    .sort((left, right) => right.start - left.start)
    .reduce((current, finding) => repairSpan(current, finding.start, finding.end), source);
}

function swiftFiles(root) {
  return execFileSync('git', ['ls-files', '-z', '--', '*.swift'], {
    cwd: root,
    encoding: 'utf8',
  })
    .split('\0')
    .filter(Boolean);
}

function readSwift(root) {
  const files = swiftFiles(root);
  return {
    files,
    readSource: (path) => readFileSync(join(root, path), 'utf8'),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const fix = process.argv.includes('--fix');
  if (process.argv.slice(2).some((arg) => arg !== '--fix')) {
    console.error('usage: node packages/shared-lib/scripts/healthkit-sync-metadata.mjs [--fix]');
    process.exitCode = 1;
  } else {
    const root = process.cwd();
    const snapshot = readSwift(root);
    if (fix) {
      const dirty = new Set(scan(snapshot).map((finding) => finding.path));
      for (const path of dirty) {
        const full = join(root, path);
        const source = readFileSync(full, 'utf8');
        const repaired = repairSource(source);
        if (repaired !== source) writeFileSync(full, repaired);
      }
    }
    const findings = scan(readSwift(root));
    console.log(JSON.stringify(findings, null, 2));
    if (findings.length) process.exitCode = 1;
  }
}
