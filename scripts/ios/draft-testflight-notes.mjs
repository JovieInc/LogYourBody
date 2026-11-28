import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const shaPattern = /^[0-9a-f]{40}$/;
const customerCategories = new Set(['feature', 'fix', 'improvement']);

function git(args, cwd) {
  try {
    return execFileSync('git', ['--no-replace-objects', ...args], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    throw new Error('Could not verify the release range in the local Git checkout.');
  }
}

function releaseRange(lastDistributed, candidate, cwd) {
  if (!shaPattern.test(lastDistributed) || !shaPattern.test(candidate)) {
    throw new Error('Last distributed and candidate must be full commit SHAs.');
  }
  if (
    git(['cat-file', '-t', lastDistributed], cwd) !== 'commit' ||
    git(['cat-file', '-t', candidate], cwd) !== 'commit'
  ) {
    throw new Error('Release boundaries must be commit objects.');
  }
  if (lastDistributed === candidate) return [];

  const range = git(
    ['rev-list', '--first-parent', '--reverse', '--ancestry-path', lastDistributed + '..' + candidate],
    cwd,
  );
  const commits = range ? range.split('\n') : [];
  if (
    commits.at(-1) !== candidate ||
    git(['show', '-s', '--format=%P', commits[0]], cwd).split(' ')[0] !== lastDistributed
  ) {
    throw new Error('The last distributed commit must be on the candidate’s first-parent history.');
  }
  return commits;
}

/** Render a draft from reviewed public metadata, never from Git titles or bodies. */
export function draftTestFlightNotes(input, { cwd = process.cwd() } = {}) {
  if (
    typeof input?.lastDistributed !== 'string' ||
    typeof input?.candidate !== 'string' ||
    !Array.isArray(input?.entries)
  ) {
    throw new Error('Expected lastDistributed, candidate, and entries.');
  }

  const range = releaseRange(input.lastDistributed, input.candidate, cwd);
  const eligible = new Set(range);
  const notesByCommit = new Map();
  for (const entry of input.entries) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error('Invalid release note metadata.');
    }
    if (
      entry.audience !== 'customer' ||
      entry.approval !== 'approved' ||
      !customerCategories.has(entry.category)
    ) {
      continue;
    }
    if (!eligible.has(entry.sha) || typeof entry.note !== 'string') {
      throw new Error('Approved note is missing copy or exact in-range commit provenance.');
    }
    const note = entry.note.trim();
    if (
      !note ||
      /[\p{C}\p{Zl}\p{Zp}<>]/u.test(entry.note) ||
      /(?:https?:\/\/|www\.|(?:^|\s)#[0-9]+|\b[A-Z]{2,}-[0-9]+\b)/iu.test(note)
    ) {
      throw new Error('Approved notes must be single-line public copy without links or ticket IDs.');
    }
    if (!notesByCommit.has(entry.sha)) notesByCommit.set(entry.sha, []);
    notesByCommit.get(entry.sha).push(note);
  }

  const notes = [...new Set(range.flatMap((sha) => notesByCommit.get(sha)?.sort() ?? []))];
  const draft = notes.map((note) => '- ' + note + '\n').join('');
  if ([...draft].length > 1000) {
    throw new Error('The candidate draft exceeds the review budget; curate the approved notes.');
  }
  return draft;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    let input;
    try {
      input = JSON.parse(readFileSync(0, 'utf8'));
    } catch {
      throw new Error('Draft input is not valid JSON.');
    }
    const draft = draftTestFlightNotes(input);
    if (draft) {
      process.stdout.write(draft);
    } else {
      process.stderr.write('No approved customer notes in the release range.\n');
      process.exitCode = 3;
    }
  } catch (error) {
    process.stderr.write(error.message + '\n');
    process.exitCode = 2;
  }
}
