import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const denylistPath = path.join(root, 'scripts/knowledge/denylist.sha256');

function compact(value) {
  return value.toLocaleLowerCase('en-US').replace(/[^a-z0-9]/g, '');
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

export function parseDenylist(text) {
  const entries = text.split(/\r?\n/).filter(Boolean).map((line) => {
    const match = line.match(/^(\d+)\t([a-f0-9]{64})$/);
    if (!match || Number(match[1]) < 4) throw new Error('Invalid private identity hash entry');
    return { length: Number(match[1]), digest: match[2] };
  });
  if (entries.length === 0) throw new Error('Private identity hash list is empty');
  return entries;
}

export function containsForbiddenIdentity(text, entries) {
  const normalized = compact(text);
  return entries.some(({ length, digest }) => {
    for (let start = 0; start <= normalized.length - length; start += 1) {
      if (sha256(normalized.slice(start, start + length)) === digest) return true;
    }
    return false;
  });
}

async function filesUnder(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(fullPath));
    else if (entry.isFile()) files.push(fullPath);
  }
  return files;
}

export async function run() {
  const entries = parseDenylist(await readFile(denylistPath, 'utf8'));
  const targets = [
    path.join(root, 'agent/skills'),
    path.join(root, 'evals/knowledge-golden'),
    path.join(root, 'evals/claims-guardrails'),
    path.join(root, 'docs/compliance'),
  ];
  const files = (await Promise.all(targets.map(filesUnder))).flat();
  if (files.length === 0) throw new Error('No public knowledge artifacts found to scan');

  const violations = [];
  for (const file of files) {
    const content = await readFile(file, 'utf8');
    if (containsForbiddenIdentity(content, entries)) {
      violations.push(path.relative(root, file) + ' contains a configured source identity');
    }
  }
  if (violations.length) throw new Error('Specifics lint failed:\n' + violations.join('\n'));
  process.stdout.write('No-specifics lint passed; scanned ' + files.length + ' public knowledge artifacts.\n');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run().catch((error) => {
    process.stderr.write((error instanceof Error ? error.message : String(error)) + '\n');
    process.exitCode = 1;
  });
}
