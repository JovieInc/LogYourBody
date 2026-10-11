import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const preload = path.join(root, 'scripts/eve/eval-recorder-preload.mjs');
const require = createRequire(import.meta.url);
const manifestPath = require.resolve('eve/package.json');
const eveRoot = path.dirname(manifestPath);

// Exercise the installed recorder and its unchanged loadedSkill assertion.
const probe = String.raw`
import { pathToFileURL } from 'node:url';
const base = ${JSON.stringify(eveRoot)};
const { deriveRunFacts } = await import(pathToFileURL(base + '/dist/src/evals/runner/derive-run-facts.js'));
const { loadedSkill } = await import(pathToFileURL(base + '/dist/src/evals/assertions/run.js'));
const request = (id, skill = 'exercise_selection') => ({ type: 'actions.requested', data: { actions: [{ kind: 'tool-call', callId: id, toolName: 'load_skill', input: { skill } }] } });
const result = (id, status = 'completed') => ({ type: 'action.result', data: { status, result: { kind: 'tool-result', callId: id, toolName: 'load_skill', output: 'actual skill output' } } });
const input = id => ({ type: 'input.requested', data: { requests: [{ action: { callId: id, toolName: 'load_skill', input: { skill: 'exercise_selection' } } }] } });
const cases = {
  requestFirst: [request('a'), result('a')],
  resultFirst: [result('a'), request('a')],
  inputRequest: [result('a'), input('a')],
  duplicateRequest: [result('a'), request('a'), request('a', 'wrong_topic')],
  wrongSkill: [result('a'), request('a', 'wrong_topic')],
  failedResult: [result('a', 'failed'), request('a')],
  orphanResult: [result('a')],
  pendingRequest: [request('a')],
  twoMatchingCalls: [result('a'), request('a'), result('b'), request('b')],
  oneMatchingPlusWrong: [result('a'), request('a'), result('b'), request('b', 'wrong_topic')],
  laterRequestTurn: [{ type: 'turn.started' }, result('a'), { type: 'turn.started' }, request('a')],
  otherFacts: [
    { type: 'subagent.started', data: { callId: 'sub', subagentName: 'helper' } },
    { type: 'subagent.completed', data: { callId: 'sub', subagentName: 'helper', output: 'child output' } },
    { type: 'message.completed', data: { finishReason: 'stop' } },
    { type: 'reasoning.completed' },
    { type: 'session.failed', data: { code: 'fixture_failure' } },
  ],
};
const output = {};
for (const [name, events] of Object.entries(cases)) {
  const derived = deriveRunFacts(events, { sessionId: 'same-session' });
  output[name] = { derived, assertion: loadedSkill('exercise_selection', { count: 1 }).evaluate({ events, derived, status: 'completed' }) };
}
console.log(JSON.stringify(output));
`;

function runProbe(repaired: boolean) {
  const args = repaired ? ['--import', preload] : [];
  const result = spawnSync(process.execPath, [...args, '--input-type=module', '--eval', probe], {
    cwd: root,
    encoding: 'utf8',
    timeout: 10_000,
  });
  expect(result.status, result.stderr).toBe(0);
  return JSON.parse(result.stdout);
}

describe('Eve knowledge-golden tool request recording', () => {
  it('reproduces the installed result-before-request defect without the preload', () => {
    const baseline = runProbe(false);
    expect(baseline.requestFirst.assertion.score).toBe(1);
    expect(baseline.resultFirst.assertion.score).toBe(0);
    expect(baseline.resultFirst.assertion.message).toContain('observed load_skill calls: {}');
  });

  it('hydrates both authoritative request boundaries while retaining the first request', () => {
    const fixed = runProbe(true);
    for (const name of ['requestFirst', 'resultFirst', 'inputRequest', 'duplicateRequest']) {
      expect(fixed[name].assertion.score, name).toBe(1);
      expect(fixed[name].derived.toolCalls).toHaveLength(1);
      expect(fixed[name].derived.toolCalls[0]).toEqual({
        name: 'load_skill',
        input: { skill: 'exercise_selection' },
        output: 'actual skill output',
        status: 'completed',
        sessionId: 'same-session',
        turnIndex: 0,
      });
    }
    expect(fixed.laterRequestTurn.derived.toolCalls[0].turnIndex).toBe(0);
  });

  it('preserves failed, pending, missing-request and exact matching-call-count gates', () => {
    const fixed = runProbe(true);
    for (const name of [
      'wrongSkill',
      'failedResult',
      'orphanResult',
      'pendingRequest',
      'twoMatchingCalls',
    ]) {
      expect(fixed[name].assertion.score, name).toBe(0);
    }
    expect(fixed.orphanResult.derived.toolCalls[0].input).toEqual({});
    expect(fixed.failedResult.derived.toolCalls[0].status).toBe('failed');
    expect(fixed.pendingRequest.derived.toolCalls[0].status).toBe('pending');
    expect(fixed.twoMatchingCalls.derived.toolCallCount).toBe(2);
    // Existing count:1 contract counts completed matching-topic calls only.
    expect(fixed.oneMatchingPlusWrong.assertion.score).toBe(1);
    expect(fixed.otherFacts.derived).toEqual(runProbe(false).otherFacts.derived);
  });

  it.each(['worker', 'fork'])('inherits the active preload in a %s', (mode) => {
    const directory = mkdtempSync(path.join(tmpdir(), 'lyb71-eve-inheritance-'));
    try {
      writeFileSync(path.join(directory, 'probe.mjs'), probe);
      const childScript =
        mode === 'worker'
          ? `import { Worker } from 'node:worker_threads';
           const child = new Worker(new URL('./probe.mjs', import.meta.url));`
          : `import { fork } from 'node:child_process';
           const child = fork(new URL('./probe.mjs', import.meta.url), [], { silent: true });
           child.stdout.pipe(process.stdout); child.stderr.pipe(process.stderr);`;
      writeFileSync(
        path.join(directory, 'parent.mjs'),
        childScript +
          `
        await new Promise((resolve, reject) => {
          child.on('error', reject);
          child.on('exit', code => code === 0 ? resolve() : reject(new Error('Child failed: ' + code)));
        });`,
      );
      const result = spawnSync(
        process.execPath,
        ['--import', preload, path.join(directory, 'parent.mjs')],
        {
          cwd: root,
          encoding: 'utf8',
          timeout: 10_000,
        },
      );
      expect(result.status, result.stderr).toBe(0);
      expect(JSON.parse(result.stdout).resultFirst.assertion.score).toBe(1);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it.each(['version', 'source'])('fails closed when the reviewed package %s changes', (changed) => {
    const directory = mkdtempSync(path.join(tmpdir(), 'lyb71-eve-guard-'));
    try {
      const fakeRoot = path.join(directory, 'node_modules/eve');
      const recorder = path.join(fakeRoot, 'dist/src/evals/runner/derive-run-facts.js');
      mkdirSync(path.dirname(recorder), { recursive: true });
      writeFileSync(
        path.join(fakeRoot, 'package.json'),
        JSON.stringify({
          name: 'eve',
          version: changed === 'version' ? '0.27.14' : '0.27.13',
          type: 'module',
          exports: { './package.json': './package.json' },
        }),
      );
      writeFileSync(
        recorder,
        readFileSync(path.join(eveRoot, 'dist/src/evals/runner/derive-run-facts.js'), 'utf8') +
          '\n',
      );
      const isolatedPreload = path.join(directory, 'preload.mjs');
      writeFileSync(isolatedPreload, readFileSync(preload));
      const result = spawnSync(process.execPath, ['--import', isolatedPreload, '--eval', ''], {
        cwd: directory,
        encoding: 'utf8',
        timeout: 10_000,
      });
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain(
        changed === 'version' ? 'this Eve version' : 'changed Eve source',
      );
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('activates the preload only for eval commands through the existing launcher', () => {
    const directory = mkdtempSync(path.join(tmpdir(), 'lyb71-eve-launcher-'));
    try {
      const corepack = path.join(directory, 'corepack');
      writeFileSync(
        corepack,
        '#!/usr/bin/env node\nconsole.log(JSON.stringify(process.argv.slice(2)))\n',
      );
      chmodSync(corepack, 0o755);
      for (const command of ['eval', 'build', 'info', 'dev']) {
        const result = spawnSync('bash', ['scripts/eve/run-node24.sh', command, '--strict'], {
          cwd: root,
          encoding: 'utf8',
          timeout: 10_000,
          env: { ...process.env, PATH: directory + path.delimiter + process.env.PATH },
        });
        expect(result.status, result.stderr).toBe(0);
        const args = JSON.parse(result.stdout);
        expect(args.slice(0, 3)).toEqual(['pnpm', 'dlx', 'node@24.12.0']);
        expect(args.slice(-3)).toEqual(['node_modules/eve/bin/eve.js', command, '--strict']);
        expect(args.filter((arg: string) => arg === '--import')).toHaveLength(
          command === 'eval' ? 1 : 0,
        );
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
