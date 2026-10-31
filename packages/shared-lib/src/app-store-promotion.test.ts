import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { resolveAppStoreBuild } from '../../../.github/scripts/resolve-app-store-build.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const workflow = readFileSync(`${root}/.github/workflows/ios-release-loop.yml`, 'utf8');
const release = readFileSync(`${root}/apps/ios/fastlane/Fastfile.release`, 'utf8');
const build = '20261029123456';
const commit = 'a'.repeat(40);
const tag = `ios-v1.2.0-testflight.${build}`;
const runUrl = 'https://github.com/JovieInc/LogYourBody/actions/runs/12345';
const env = {
  BUILD_NUMBER: build,
  PAYWALL_VERIFIED_BUILD_NUMBER: build,
  GITHUB_REF: 'refs/heads/main',
  GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
  GITHUB_SERVER_URL: new URL(runUrl).origin,
};

function fixture() {
  const refs = `${'b'.repeat(40)}\trefs/tags/${tag}\n${commit}\trefs/tags/${tag}^{}\n`;
  const evidence = {
    tag_name: tag,
    draft: false,
    body: `**Build Number**: ${build}\n**Deployment**: testflight\n- **Commit**: ${commit}\n- **Workflow**: [View Run](${runUrl})\n`,
  };
  const run = {
    head_sha: commit,
    head_branch: 'main',
    path: '.github/workflows/ios-release-loop.yml',
    status: 'completed',
    conclusion: 'success',
  };
  const job = {
    name: 'Deploy to TestFlight / Deploy to TestFlight (alpha)',
    conclusion: 'success',
    steps: ['Upload to TestFlight', 'Wait for processing and assign groups'].map((name) => ({
      name,
      conclusion: 'success',
    })),
  };
  const data = { refs, evidence, run, pages: [{ jobs: [job] }] };
  const calls: string[][] = [];
  const command = (command: string, args: string[]) => {
    calls.push([command, ...args]);
    if (command === 'git') return data.refs;
    expect(command).toBe('gh');
    expect(args[0]).toBe('api');
    expect(args).not.toContain('--method');
    if (args[1].includes('/releases/')) return JSON.stringify(data.evidence);
    if (args[1].includes('/jobs?')) {
      expect(args.slice(2)).toEqual(['--paginate', '--slurp']);
      return JSON.stringify(data.pages);
    }
    return JSON.stringify(data.run);
  };
  return { data, calls, command };
}

const jobSource = (name: string) =>
  workflow.match(new RegExp(`^  ${name}:\\n[\\s\\S]*?(?=^  [\\w-]+:|$(?![\\s\\S]))`, 'm'))?.[0] ||
  '';

describe('App Store promotion provenance', () => {
  it('selects the peeled TestFlight tag commit even when dispatch HEAD has moved', () => {
    const f = fixture();
    expect(resolveAppStoreBuild({ ...env, GITHUB_SHA: 'c'.repeat(40) }, f.command)).toEqual({
      tag,
      version: '1.2.0',
      commit,
      build_number: build,
      testflight_run: runUrl,
    });
    // The processing receipt may be on a later page of the run's jobs.
    f.data.pages.unshift({ jobs: [] });
    expect(resolveAppStoreBuild(env, f.command).commit).toBe(commit);
    f.data.refs = `${commit}\trefs/tags/${tag}\n`; // lightweight tags also resolve
    expect(resolveAppStoreBuild(env, f.command).commit).toBe(commit);
  });

  it.each([
    { BUILD_NUMBER: '' },
    { BUILD_NUMBER: undefined },
    { BUILD_NUMBER: '1\n2' },
    { BUILD_NUMBER: '$(touch /tmp/unsafe)' },
    { PAYWALL_VERIFIED_BUILD_NUMBER: '' },
    { PAYWALL_VERIFIED_BUILD_NUMBER: 'another-build' },
    { GITHUB_REF: 'refs/heads/feature' },
    { GITHUB_REPOSITORY: '../invalid' },
    { GITHUB_SERVER_URL: '' },
  ])('rejects missing/mismatched dispatch input before any external command: %j', (override) => {
    const f = fixture();
    expect(() => resolveAppStoreBuild({ ...env, ...override }, f.command)).toThrow();
    expect(f.calls).toEqual([]);
  });

  it.each([
    'missing-tag',
    'ambiguous-tag',
    'draft',
    'wrong-tag',
    'wrong-build',
    'wrong-commit',
    'wrong-deployment',
    'missing-run',
    'wrong-run-commit',
    'wrong-branch',
    'wrong-workflow',
    'pending-run',
    'failed-run',
    'missing-upload',
    'failed-processing',
    'failed-job',
    'missing-steps',
  ])('fails closed for %s', (failure) => {
    const f = fixture();
    if (failure === 'missing-tag')
      f.data.refs = `${commit}\trefs/tags/ios-v1.2.0-testflight.${build}9\ninvalid`;
    if (failure === 'ambiguous-tag')
      f.data.refs += `${commit}\trefs/tags/ios-v1.3.0-testflight.${build}\n`;
    if (failure === 'draft') f.data.evidence.draft = true;
    if (failure === 'wrong-tag') f.data.evidence.tag_name = 'other';
    if (failure === 'wrong-build')
      f.data.evidence.body = f.data.evidence.body.replace(build, `${build}9`);
    if (failure === 'wrong-commit')
      f.data.evidence.body = f.data.evidence.body.replace(commit, 'd'.repeat(40));
    if (failure === 'wrong-deployment')
      f.data.evidence.body = f.data.evidence.body.replace('testflight\n', 'app_store\n');
    if (failure === 'missing-run')
      f.data.evidence.body = f.data.evidence.body.replace(runUrl, 'https://example.com');
    if (failure === 'wrong-run-commit') f.data.run.head_sha = 'c'.repeat(40);
    if (failure === 'wrong-branch') f.data.run.head_branch = 'feature';
    if (failure === 'wrong-workflow') f.data.run.path = '.github/workflows/other.yml';
    if (failure === 'pending-run') f.data.run.status = 'in_progress';
    if (failure === 'failed-run') f.data.run.conclusion = 'failure';
    if (failure === 'missing-upload') f.data.pages[0].jobs[0].steps.shift();
    if (failure === 'failed-processing') f.data.pages[0].jobs[0].steps[1].conclusion = 'failure';
    if (failure === 'failed-job') f.data.pages[0].jobs[0].conclusion = 'failure';
    if (failure === 'missing-steps') f.data.pages[0].jobs[0].steps = [];
    expect(() => resolveAppStoreBuild(env, f.command)).toThrow();
  });
});

describe('App Store promotion workflow', () => {
  it('runs App Store promotion independently of every fresh-build job', () => {
    for (const name of [
      'pin-release-tag',
      'validate-release',
      'bind-release-version',
      'build-release',
      'deploy-testflight',
    ]) {
      expect(jobSource(name), name).toContain(
        "if: github.event.inputs.release_type != 'app_store'",
      );
    }
    const select = jobSource('select-app-store-build');
    expect(select).toContain('resolve-app-store-build.mjs');
    expect(select).toContain('BUILD_NUMBER: ${{ inputs.build_number }}');
    expect(select).toContain(
      'PAYWALL_VERIFIED_BUILD_NUMBER: ${{ inputs.paywall_verified_build_number }}',
    );
    expect(select).not.toContain('write');
    const deploy = jobSource('deploy-app-store');
    expect(deploy).toContain('needs: select-app-store-build');
    expect(deploy).not.toMatch(
      /download-artifact|setup-ios-build|sync-match|ipa_path:|build_release/,
    );
    expect(workflow).not.toContain('paywall_testflight_verified');
    expect(jobSource('create-release')).not.toContain('deploy-app-store');
  });

  it('validates before pricing writes and passes the selected build to submission and the summary', () => {
    const deploy = jobSource('deploy-app-store');
    expect(deploy.indexOf('fastlane validate_app_store_build')).toBeGreaterThan(0);
    expect(deploy.indexOf('fastlane validate_app_store_build')).toBeLessThan(
      deploy.indexOf('ensure-app-store-free-pricing.rb'),
    );
    expect(deploy).toContain('build_number:"$BUILD_NUMBER"');
    expect(deploy).toContain('paywall_verified_build_number:"$PAYWALL_VERIFIED_BUILD_NUMBER"');
    for (const output of ['version', 'build_number', 'tag', 'commit', 'testflight_run']) {
      expect(deploy).toContain(`needs.select-app-store-build.outputs.${output}`);
    }
    expect(deploy).toContain('GITHUB_STEP_SUMMARY');
    // Explicit false inputs must remain false; GitHub expression || defaults lose them.
    for (const input of ['submit_for_review', 'phased_release']) {
      expect(deploy).toContain(`\${{ inputs.${input} }}`);
      expect(deploy).not.toContain(`inputs.${input} ||`);
    }
    expect(deploy).toContain('automatic_release:false');
    expect(workflow).not.toContain('inputs.automatic_release');
    expect(workflow).not.toMatch(/automatic_release:\s*\n/);
    const directory = mkdtempSync(`${tmpdir()}/lyb-promotion-summary-`);
    try {
      const summary = deploy.match(/ {10}\{\n[\s\S]*?\} >> "\$GITHUB_STEP_SUMMARY"/)?.[0];
      expect(summary).toBeDefined();
      execFileSync('bash', ['-eu', '-c', summary!], {
        env: {
          ...process.env,
          VERSION_NAME: '1.2.0',
          BUILD_NUMBER: build,
          RELEASE_TAG: tag,
          RELEASE_COMMIT: commit,
          TESTFLIGHT_RUN: runUrl,
          SUBMIT_FOR_REVIEW: 'true',
          GITHUB_ACTOR: 'tester',
          GITHUB_STEP_SUMMARY: `${directory}/summary`,
        },
      });
      const text = readFileSync(`${directory}/summary`, 'utf8');
      for (const value of [build, tag, commit, runUrl, '@tester']) expect(text).toContain(value);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

describe('App Store promotion Fastlane behavior', () => {
  it('requires exact attestation and processed ASC identity, then submits without a binary', () => {
    const lanes = ['validate_app_store_build', 'submit_app_store'].map((name) => {
      const lane = release.match(
        new RegExp(` {2}lane :${name} do \\|options\\|[\\s\\S]*?\\n {2}end`),
      )?.[0];
      expect(lane, name).toBeDefined();
      return lane;
    });
    const directory = mkdtempSync(`${tmpdir()}/lyb-app-store-promotion-`);
    const source = `${directory}/lanes.rb`;
    writeFileSync(source, ['app_store_app_id = -> { "6755209876" }', ...lanes].join('\n'));
    const options = {
      version_name: '1.2.0',
      build_number: build,
      paywall_verified_build_number: build,
      submit_for_review: true,
      automatic_release: false,
      phased_release: true,
    };
    const cases = [
      {},
      { options: { submit_for_review: false, automatic_release: false, phased_release: false } },
      {
        options: { submit_for_review: 'true', automatic_release: 'false', phased_release: 'false' },
      },
      { options: { build_number: '' } },
      { options: { build_number: 'invalid' } },
      { options: { version_name: '' } },
      { options: { paywall_verified_build_number: '' } },
      { options: { paywall_verified_build_number: 'another-build' } },
      { options: { ipa_path: 'fresh.ipa' } },
      { count: 0 },
      { count: 2 },
      { build: { processing_state: 'PROCESSING' } },
      { build: { processing_state: 'FAILED' } },
      { build: { processing_state: 'INVALID' } },
      { build: { expired: true } },
      { build: { version: 'different' } },
      { build: { app_version: '1.3.0' } },
      { build: { platform: 'MAC_OS' } },
      { options: { automatic_release: true, submit_for_review: false } },
      { options: { phased_release: 'invalid' } },
      { failure: 'A review submission is already in progress' },
      { failure: 'ASC unavailable' },
      ...[true, 'true', '1', 'yes', 'y', 'on'].map((value) => ({
        options: { automatic_release: value },
      })),
      { options: { automatic_release: 'invalid' } },
    ];
    try {
      const result = JSON.parse(
        execFileSync(
          'ruby',
          [
            '-rjson',
            '-rostruct',
            '-rcoverage',
            '-e',
            String.raw`
module UI
  def self.user_error!(message); raise message; end
end
module Spaceship
  module ConnectAPI
    class Build
      def self.all(**options)
        $reads << options
        Array.new($entry.fetch(:count, 1)) { OpenStruct.new({ version: $build, app_version: '1.2.0', platform: 'IOS', processing_state: 'VALID', expired: false }.merge($entry.fetch(:build, {}))) }
      end
    end
  end
end
def lane(name, &block); define_singleton_method(name) { |options| block.call(options) }; end
def setup_app_store_connect_api; $auth += 1; end
def upload_to_app_store(**options)
  raise $entry[:failure] if $entry[:failure]
  $writes << options
end
Coverage.start
load ARGV.fetch(0)
data = JSON.parse(STDIN.read, symbolize_names: true)
$build = data.fetch(:options).fetch(:build_number)
results = data.fetch(:cases).map do |entry|
  $entry = entry
  $reads = []; $writes = []; $auth = 0
  error = nil
  begin
    submit_app_store(data.fetch(:options).merge(entry.fetch(:options, {})))
  rescue => e
    error = e.message
  end
  { reads: $reads, writes: $writes, auth: $auth, error: error }
end
coverage = Coverage.result.fetch(ARGV.fetch(0)).drop(1).compact
puts JSON.generate(results: results, covered: coverage.count { |n| n > 0 }, total: coverage.length)
`,
            source,
          ],
          { encoding: 'utf8', input: JSON.stringify({ options, cases }), timeout: 10000 },
        ),
      );
      for (const index of [0, 1, 2]) {
        const r = result.results[index];
        expect(r.error).toBeNull();
        expect(r.reads).toEqual([
          { app_id: '6755209876', version: '1.2.0', build_number: build, platform: 'IOS' },
        ]);
        expect(r.writes).toHaveLength(1);
        expect(r.writes[0]).toMatchObject({
          app_version: '1.2.0',
          build_number: build,
          platform: 'ios',
          skip_binary_upload: true,
          automatic_release: false,
        });
        expect(r.writes[0]).not.toHaveProperty('ipa');
      }
      expect(result.results[1].writes[0]).toMatchObject({
        submit_for_review: false,
        automatic_release: false,
        phased_release: false,
      });
      for (let index = 3; index < cases.length; index++) {
        expect(result.results[index].error, JSON.stringify(cases[index])).toBeTruthy();
        expect(result.results[index].writes).toEqual([]);
        if (index <= 8) {
          expect(result.results[index].auth).toBe(0);
          expect(result.results[index].reads).toEqual([]);
        }
      }
      expect(result.results[18].error).toContain('health gate');
      expect(result.results[20].error).toBe('A review submission is already in progress');
      expect(result.results[21].error).toBe('ASC unavailable');
      for (const resultCase of result.results.slice(22, 28)) {
        expect(resultCase.error).toContain('health gate');
      }
      console.log(
        `App Store promotion Ruby coverage: ${result.covered}/${result.total} executable lines; ${cases.length} behavior cases`,
      );
      expect(result.covered / result.total).toBeGreaterThanOrEqual(0.95);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
