import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  commitFromLsRemote,
  isReleaseTag,
  isWorkflowScopeDenial,
  marketingVersionFromPbxproj,
  releaseTagName,
  releaseTargetMode,
} from './ios-release-tag.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const pinScript = join(root, '.github/scripts/pin-ios-release-tag.sh');
const createScript = join(root, '.github/scripts/create-ios-github-release.sh');
const pbxproj = join(root, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj');
const sha = '8f05c37800efd9aa595421f340f2e8bbfd6e45f4';
const otherSha = 'd9ed855d386f47fd3ec9e67a78f57a021b6b28ff';

test('marketing version parser takes the first semver and matches awk on the app project', () => {
  const fixture = [
    'MARKETING_VERSION = 1.2.0;',
    'MARKETING_VERSION = 1.0;',
    'MARKETING_VERSION = $(INHERITED);',
    'OTHER = 9.9.9;',
  ].join('\n');
  assert.equal(marketingVersionFromPbxproj(fixture), '1.2.0');
  assert.equal(marketingVersionFromPbxproj('no version'), null);
  assert.equal(marketingVersionFromPbxproj(null), null);

  const project = readFileSync(pbxproj, 'utf8');
  const awk = spawnSync('awk', [
    '-F',
    ' = ',
    '/MARKETING_VERSION = / { gsub(/[;[:space:]]/, "", $2); if ($2 ~ /^[0-9]+[.][0-9]+/) { print $2; exit } }',
  ], { input: project, encoding: 'utf8' });
  assert.equal(awk.status, 0);
  assert.equal(marketingVersionFromPbxproj(project), awk.stdout.trim());
  assert.match(marketingVersionFromPbxproj(project), /^[0-9]+\.[0-9]+/);
});

test('release tags stay pinned to the deployment type and reject loose names', () => {
  assert.equal(releaseTagName({
    version: '1.2.0',
    buildNumber: '20261017003151',
    deploymentType: 'testflight',
  }), 'ios-v1.2.0-testflight.20261017003151');
  assert.equal(releaseTagName({
    version: '1.2.0',
    buildNumber: 'ignored',
    deploymentType: 'app_store',
  }), 'ios-v1.2.0');
  for (const input of [
    { version: 'v1.2.0', buildNumber: '20261017003151', deploymentType: 'testflight' },
    { version: '1.2.0', buildNumber: '203', deploymentType: 'testflight' },
    { version: '1.2.0', buildNumber: '20261017003151', deploymentType: 'beta' },
    { version: '1.2.0\n', buildNumber: '20261017003151', deploymentType: 'testflight' },
  ]) assert.throws(() => releaseTagName(input));
});

test('only iOS release tags may be deleted', () => {
  assert.equal(isReleaseTag('ios-v1.2.0-testflight.20261017003151'), true);
  assert.equal(isReleaseTag('ios-v1.2.0'), true);
  assert.equal(isReleaseTag('refs/heads/main'), false);
  assert.equal(isReleaseTag('ios-v1.2.0-testflight.20261017003151; rm -rf'), false);
  assert.equal(isReleaseTag(''), false);
});

test('workflow scope denials are the known git and releases API messages only', () => {
  assert.equal(isWorkflowScopeDenial(
    'HTTP 403: Resource not accessible by integration (https://api.github.com/repos/JovieInc/LogYourBody/releases)',
  ), true);
  assert.equal(isWorkflowScopeDenial(
    'refusing to allow a GitHub App to create or update workflow .github/workflows/ci.yml without workflows permission',
  ), true);
  assert.equal(isWorkflowScopeDenial('fatal: unable to access'), false);
  assert.equal(isWorkflowScopeDenial(''), false);
});

test('ls-remote peel prefers the annotated commit and target mode refuses a different tag', () => {
  const tag = 'ios-v1.2.0-testflight.20261017003151';
  const output = [
    `${otherSha}\trefs/tags/${tag}`,
    `${sha}\trefs/tags/${tag}^{}`,
    `${'a'.repeat(40)}\trefs/tags/ios-v1.0.0`,
  ].join('\n');
  assert.equal(commitFromLsRemote(output, tag), sha);
  assert.equal(commitFromLsRemote(`${sha}\trefs/tags/${tag}\n`, tag), sha);
  assert.equal(commitFromLsRemote('', tag), null);
  assert.equal(releaseTargetMode({ tagCommit: null, headSha: sha }), 'create');
  assert.equal(releaseTargetMode({ tagCommit: sha, headSha: sha }), 'existing');
  assert.equal(releaseTargetMode({ tagCommit: otherSha, headSha: sha }), 'mismatch');
  assert.throws(() => releaseTargetMode({ tagCommit: sha, headSha: 'main' }));
});

const gitEnv = (dir) => ({
  ...process.env,
  HOME: dir,
  GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'Release Tag Test',
  GIT_AUTHOR_EMAIL: 'release-tag-test@example.com',
  GIT_COMMITTER_NAME: 'Release Tag Test',
  GIT_COMMITTER_EMAIL: 'release-tag-test@example.com',
});

const git = (dir, args) => {
  const result = spawnSync('git', args, { cwd: dir, env: gitEnv(dir), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};

const initRepo = () => {
  const dir = mkdtempSync(join(tmpdir(), 'ios-release-tag-'));
  const remote = join(dir, 'remote.git');
  const work = join(dir, 'work');
  spawnSync('git', ['init', '--bare', remote], { encoding: 'utf8' });
  mkdirSync(join(work, 'apps/ios/LogYourBody.xcodeproj'), { recursive: true });
  writeFileSync(
    join(work, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'),
    'MARKETING_VERSION = 1.2.0;\nMARKETING_VERSION = 1.0;\n',
  );
  git(work, ['init', '-b', 'main']);
  git(work, ['add', '.']);
  git(work, ['commit', '-m', 'fixture']);
  git(work, ['remote', 'add', 'origin', remote]);
  git(work, ['push', '-u', 'origin', 'main']);
  return { dir, remote, work, head: git(work, ['rev-parse', 'HEAD']) };
};

const runScript = (script, work, env, args = []) => {
  const output = join(work, 'github-output.txt');
  writeFileSync(output, '');
  return spawnSync('bash', [script, ...args], {
    cwd: work,
    encoding: 'utf8',
    env: { ...gitEnv(work), GITHUB_OUTPUT: output, ...env },
  });
};

const outputMap = (work) => Object.fromEntries(
  readFileSync(join(work, 'github-output.txt'), 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    }),
);

test('pin script pushes the TestFlight tag at HEAD before main can move', () => {
  const repo = initRepo();
  const result = runScript(pinScript, repo.work, {
    GITHUB_SHA: repo.head,
    RELEASE_TYPE: 'testflight',
  });
  assert.equal(result.status, 0, result.stderr);
  const outputs = outputMap(repo.work);
  assert.equal(outputs.version, '1.2.0');
  assert.match(outputs.build_number, /^[0-9]{14}$/);
  assert.equal(outputs.tag, `ios-v1.2.0-testflight.${outputs.build_number}`);
  assert.equal(outputs.pinned, 'true');
  assert.equal(outputs.created_tag, 'true');
  const peeled = git(repo.remote, ['rev-parse', `${outputs.tag}^{}`]);
  assert.equal(peeled, repo.head);
  rmSync(repo.dir, { recursive: true, force: true });
});

test('pin script does not claim a tag that was already on this commit', () => {
  const repo = initRepo();
  const bin = join(repo.dir, 'bin');
  mkdirSync(bin);
  const fakeDate = join(bin, 'date');
  writeFileSync(fakeDate, `#!/bin/bash
if [[ "$1" == "-u" ]]; then
  echo 20261017003151
  exit 0
fi
exec /usr/bin/date "$@"
`);
  chmodSync(fakeDate, 0o755);
  const env = {
    GITHUB_SHA: repo.head,
    RELEASE_TYPE: 'testflight',
    PATH: `${bin}:${process.env.PATH}`,
  };
  const first = runScript(pinScript, repo.work, env);
  assert.equal(first.status, 0, first.stderr);
  assert.equal(outputMap(repo.work).created_tag, 'true');
  const second = runScript(pinScript, repo.work, env);
  assert.equal(second.status, 0, second.stderr);
  const outputs = outputMap(repo.work);
  assert.equal(outputs.pinned, 'true');
  assert.equal(outputs.created_tag, 'false');
  assert.equal(outputs.tag, 'ios-v1.2.0-testflight.20261017003151');
  rmSync(repo.dir, { recursive: true, force: true });
});

test('pin script continues without a tag when workflow scope is refused', () => {
  const repo = initRepo();
  const bin = join(repo.dir, 'bin');
  mkdirSync(bin);
  const fakeGit = join(bin, 'git');
  writeFileSync(fakeGit, `#!/bin/bash
if [[ "$1" == "push" && "$*" == *refs/tags/* ]]; then
  echo "refusing to allow a GitHub App to create or update workflow .github/workflows/ci.yml without workflows permission" >&2
  exit 1
fi
exec /usr/bin/git "$@"
`);
  chmodSync(fakeGit, 0o755);
  const result = runScript(pinScript, repo.work, {
    GITHUB_SHA: repo.head,
    RELEASE_TYPE: 'testflight',
    PATH: `${bin}:${process.env.PATH}`,
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(`${result.stdout}\n${result.stderr}`, /::warning::/);
  const outputs = outputMap(repo.work);
  assert.equal(outputs.pinned, 'false');
  assert.equal(outputs.created_tag, 'false');
  assert.match(outputs.tag, /^ios-v1\.2\.0-testflight\.[0-9]{14}$/);
  rmSync(repo.dir, { recursive: true, force: true });
});

test('pin script deletes only the tag it created', () => {
  const repo = initRepo();
  const pinned = runScript(pinScript, repo.work, {
    GITHUB_SHA: repo.head,
    RELEASE_TYPE: 'testflight',
  });
  assert.equal(pinned.status, 0, pinned.stderr);
  const { tag } = outputMap(repo.work);
  const deleted = runScript(pinScript, repo.work, { TAG: tag }, ['delete']);
  assert.equal(deleted.status, 0, deleted.stderr);
  const listed = spawnSync('git', ['ls-remote', '--tags', 'origin', tag], {
    cwd: repo.work,
    encoding: 'utf8',
  });
  assert.equal(listed.stdout.trim(), '');
  rmSync(repo.dir, { recursive: true, force: true });
});

const fakeGh = (work, { viewStatus = 1, createStatus = 0, createStderr = '' } = {}) => {
  const bin = join(work, 'bin');
  mkdirSync(bin, { recursive: true });
  const log = join(work, 'gh.log');
  writeFileSync(join(bin, 'gh'), `#!/bin/bash
printf '%s\\n' "$*" >> ${JSON.stringify(log)}
if [[ "$1" == "release" && "$2" == "view" ]]; then
  exit ${viewStatus}
fi
if [[ -n ${JSON.stringify(createStderr)} ]]; then
  echo ${JSON.stringify(createStderr)} >&2
fi
exit ${createStatus}
`);
  chmodSync(join(bin, 'gh'), 0o755);
  return { bin, log };
};

test('release publish uses the existing tag and does not send --target', () => {
  const repo = initRepo();
  const tag = 'ios-v1.2.0-testflight.20261017003151';
  git(repo.work, ['tag', '-a', tag, '-m', 'pinned']);
  git(repo.work, ['push', 'origin', `refs/tags/${tag}`]);
  const gh = fakeGh(repo.work);
  const result = runScript(createScript, repo.work, {
    GITHUB_SHA: repo.head,
    GITHUB_SERVER_URL: 'https://example.com',
    GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
    GITHUB_RUN_ID: '38986790647',
    RELEASE_TYPE: 'testflight',
    RELEASE_VERSION: '1.2.0',
    RELEASE_BUILD: '20261017003151',
    RELEASE_ACTOR: 'github-merge-queue[bot]',
    PATH: `${gh.bin}:${process.env.PATH}`,
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const calls = readFileSync(gh.log, 'utf8');
  assert.match(calls, /release create ios-v1\.2\.0-testflight\.20261017003151/);
  assert.doesNotMatch(calls, /--target/);
  rmSync(repo.dir, { recursive: true, force: true });
});

test('release publish warns instead of failing when the unpinned SHA is refused', () => {
  const repo = initRepo();
  const gh = fakeGh(repo.work, {
    createStatus: 1,
    createStderr: 'HTTP 403: Resource not accessible by integration (https://api.github.com/repos/JovieInc/LogYourBody/releases)',
  });
  const result = runScript(createScript, repo.work, {
    GITHUB_SHA: repo.head,
    GITHUB_SERVER_URL: 'https://example.com',
    GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
    GITHUB_RUN_ID: '38986790647',
    RELEASE_TYPE: 'testflight',
    RELEASE_VERSION: '1.2.0',
    RELEASE_BUILD: '20261017004754',
    RELEASE_ACTOR: 'github-merge-queue[bot]',
    PATH: `${gh.bin}:${process.env.PATH}`,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(`${result.stdout}\n${result.stderr}`, /::warning::/);
  const calls = readFileSync(gh.log, 'utf8');
  assert.match(calls, new RegExp(`--target ${repo.head}`));
  rmSync(repo.dir, { recursive: true, force: true });
});

test('release publish still fails on errors that are not the workflow scope refusal', () => {
  const repo = initRepo();
  const gh = fakeGh(repo.work, { createStatus: 1, createStderr: 'fatal: unable to access' });
  const result = runScript(createScript, repo.work, {
    GITHUB_SHA: repo.head,
    GITHUB_SERVER_URL: 'https://example.com',
    GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
    GITHUB_RUN_ID: '1',
    RELEASE_TYPE: 'testflight',
    RELEASE_VERSION: '1.2.0',
    RELEASE_BUILD: '20261017004754',
    RELEASE_ACTOR: 'tester',
    PATH: `${gh.bin}:${process.env.PATH}`,
  });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /::warning::/);
  rmSync(repo.dir, { recursive: true, force: true });
});

test('release workflow pins the tag before validation and publishes through the script', () => {
  const workflow = readFileSync(join(root, '.github/workflows/ios-release-loop.yml'), 'utf8');
  const pinAt = workflow.indexOf('  pin-release-tag:');
  const validateAt = workflow.indexOf('  validate-release:');
  assert.ok(pinAt > 0 && validateAt > pinAt);
  assert.match(workflow, /needs: pin-release-tag/);
  assert.match(workflow, /pin-ios-release-tag\.sh/);
  assert.match(workflow, /create-ios-github-release\.sh/);
  assert.doesNotMatch(workflow, /gh release create/);
  assert.match(workflow, /created_tag == 'true'/);
});
