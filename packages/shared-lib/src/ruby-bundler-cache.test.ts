import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { expect, it } from 'vitest';

const action = readFileSync(
  new URL('../../../.github/actions/setup-ruby-bundler/action.yml', import.meta.url),
  'utf8',
);

function runtimeOutputs(identity: string, fails = false) {
  const step = action.split('      id: ruby-version\n')[1].split('\n    - name:')[0];
  const script = step.split('      run: ')[1].replace(/^\|\n/, '').replace(/^ {8}/gm, '');
  const directory = mkdtempSync(`${tmpdir()}/lyb-ruby-cache-`);
  try {
    const result = spawnSync(
      'bash',
      [
        '-e',
        '-o',
        'pipefail',
        '-c',
        `
        ruby() {
          if [[ "$*" == '-v' ]]; then
            printf '%s\n' 'ruby 3.1.7p261 (2025-03-26 revision 0) [arm64-darwin24]'
          else
            [[ "$FAIL_IDENTITY" == 'false' ]] || return 42
            printf '%s\n' "$RUBY_IDENTITY"
          fi
        }
        ${script}
      `,
      ],
      {
        encoding: 'utf8',
        env: {
          ...process.env,
          GITHUB_OUTPUT: `${directory}/output`,
          RUBY_IDENTITY: identity,
          FAIL_IDENTITY: String(fails),
        },
      },
    );
    return {
      status: result.status,
      outputs: Object.fromEntries(
        readFileSync(`${directory}/output`, 'utf8')
          .trim()
          .split('\n')
          .map((line) => line.split('=')),
      ),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function cacheSettings(identity: string, architecture = 'ARM64', environment = 'self-hosted') {
  const { status, outputs } = runtimeOutputs(identity);
  expect(status).toBe(0);
  const values: Record<string, string> = {
    'runner.os': 'macOS',
    'runner.arch': architecture,
    'runner.environment': environment,
    'inputs.working-directory': 'apps/ios',
    'inputs.cache-key-prefix': 'ios-gems',
    'steps.gemfile-hash.outputs.hash': 'lock-hash',
    ...Object.fromEntries(
      Object.entries(outputs).map(([key, value]) => [`steps.ruby-version.outputs.${key}`, value]),
    ),
  };
  const render = (text: string) =>
    text.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_, key: string) => {
      if (!(key in values)) throw new Error(`Unexpected action expression: ${key}`);
      return values[key];
    });
  const cache = action.split('    - name: Cache Ruby dependencies\n')[1].split('\n    - name:')[0];
  const rendered = render(cache);
  return {
    key: rendered.match(/ {8}key: (.+)/)?.[1],
    restore: rendered.split('        restore-keys: |\n')[1].trim(),
    path: rendered.match(/ {8}path: (.+)/)?.[1],
  };
}

it('isolates cached native gems and installed bundles for different builds of the same Ruby version', () => {
  const runtime = 'ruby 3.1.7p261\narm64-darwin24\n/opt/homebrew/Cellar/ruby@3.1/3.1.7_1';
  const homebrew = cacheSettings(runtime);
  const hosted = cacheSettings(
    'ruby 3.1.7p261\narm64-darwin24\n/Users/runner/hostedtoolcache/Ruby/3.1.7',
  );
  expect(homebrew).toEqual(cacheSettings(runtime));
  expect(homebrew.key).not.toBe(hosted.key);
  expect(homebrew.path).not.toBe(hosted.path);
  expect(homebrew.key?.startsWith(hosted.restore)).toBe(false);
  expect(hosted.key?.startsWith(homebrew.restore)).toBe(false);
  expect(homebrew.key).not.toBe(cacheSettings(runtime, 'X64').key);
  expect(homebrew.key).not.toBe(cacheSettings(runtime, 'ARM64', 'github-hosted').key);
  const bundlePath = action.match(/bundle config (?:set --local )?path (.+)/)?.[1];
  expect(`\${{ inputs.working-directory }}/${bundlePath}`).toBe(
    action.match(/ {8}path: (.+)/)?.[1],
  );
  expect(bundlePath).toContain('steps.ruby-version.outputs.identity');
});

it('stops setup when the Ruby runtime identity cannot be read', () => {
  expect(runtimeOutputs('', true).status).toBe(42);
});
