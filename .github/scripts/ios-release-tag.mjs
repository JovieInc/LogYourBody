import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Tag and GitHub Release decisions for the iOS release loop.
//
// GITHUB_TOKEN cannot satisfy the Releases API workflow scope. Creating a
// release whose target commit's .github/workflows tree differs from the
// default branch returns HTTP 403 "Resource not accessible by integration".
// Pushing that tag with git fails the same way ("without workflows permission").
// The tag has to be created while the built commit is still the default
// branch tip. Once it exists, the release is published without --target.

const VERSION_PATTERN = /^[0-9]+\.[0-9]+(?:\.[0-9]+)?$/;
const BUILD_PATTERN = /^[0-9]{14}$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;

export function marketingVersionFromPbxproj(text) {
  if (typeof text !== 'string') return null;
  for (const line of text.split('\n')) {
    const match = line.match(/MARKETING_VERSION = ([^;]+);/);
    if (!match) continue;
    const value = match[1].trim();
    if (VERSION_PATTERN.test(value)) return value;
  }
  return null;
}

export function releaseTagName({ version, buildNumber, deploymentType }) {
  if (!VERSION_PATTERN.test(version ?? '')) {
    throw new Error(`Invalid release version: ${version}`);
  }
  const base = `ios-v${version}`;
  if (deploymentType === 'app_store') return base;
  if (deploymentType !== 'testflight') {
    throw new Error(`Invalid release type: ${deploymentType}`);
  }
  if (!BUILD_PATTERN.test(buildNumber ?? '')) {
    throw new Error(`Invalid build number: ${buildNumber}`);
  }
  return `${base}-testflight.${buildNumber}`;
}

export function isWorkflowScopeDenial(text) {
  const body = String(text ?? '');
  return (
    body.includes('Resource not accessible by integration') ||
    body.includes('without workflows permission') ||
    body.includes('refusing to allow a GitHub App to create or update workflow')
  );
}

// ls-remote prints the tag object and, for annotated tags, a peeled commit on
// the "^{}" line. A lightweight tag has only the direct line, which is the commit.
export function commitFromLsRemote(output, tag) {
  if (typeof output !== 'string' || typeof tag !== 'string' || tag.length === 0) return null;
  const peeledSuffix = `refs/tags/${tag}^{}`;
  const directSuffix = `refs/tags/${tag}`;
  let direct = null;
  for (const line of output.split('\n')) {
    const [sha, ref] = line.trim().split(/\s+/);
    if (!sha || !ref) continue;
    if (ref === peeledSuffix) return sha;
    if (ref === directSuffix) direct = sha;
  }
  return direct;
}

export function releaseTargetMode({ tagCommit, headSha }) {
  if (tagCommit == null || tagCommit === '') return 'create';
  if (!SHA_PATTERN.test(headSha ?? '') || !SHA_PATTERN.test(tagCommit)) {
    throw new Error(`Invalid head SHA: ${headSha}`);
  }
  if (tagCommit === headSha) return 'existing';
  return 'mismatch';
}

export function isReleaseTag(tag) {
  return /^ios-v[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-testflight\.[0-9]{14})?$/.test(tag ?? '');
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    throw new Error(`Missing ${name}`);
  }
  return process.argv[index + 1];
}

function main() {
  const command = process.argv[2];
  if (command === 'version') {
    const version = marketingVersionFromPbxproj(readFileSync(process.argv[3], 'utf8'));
    if (!version) throw new Error('Unable to resolve MARKETING_VERSION');
    process.stdout.write(version);
    return;
  }
  if (command === 'tag') {
    process.stdout.write(releaseTagName({
      version: argument('--version'),
      buildNumber: argument('--build'),
      deploymentType: argument('--deployment'),
    }));
    return;
  }
  if (command === 'scope-denied') {
    process.exit(isWorkflowScopeDenial(readFileSync(0, 'utf8')) ? 0 : 1);
  }
  if (command === 'peeled-commit') {
    const commit = commitFromLsRemote(readFileSync(0, 'utf8'), argument('--tag'));
    if (commit) process.stdout.write(commit);
    return;
  }
  if (command === 'target-mode') {
    const tagCommit = argument('--tag-commit');
    process.stdout.write(releaseTargetMode({
      tagCommit: tagCommit === '-' ? null : tagCommit,
      headSha: argument('--head'),
    }));
    return;
  }
  if (command === 'valid-tag') {
    process.exit(isReleaseTag(argument('--tag')) ? 0 : 1);
  }
  throw new Error(`Unknown command: ${command ?? ''}`);
}

const entry = process.argv[1] ? resolve(process.argv[1]) : '';
if (entry === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
