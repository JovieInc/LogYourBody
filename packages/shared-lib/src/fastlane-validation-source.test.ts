import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const fastfilePath = fileURLToPath(new URL('../../../apps/ios/fastlane/Fastfile', import.meta.url));

type Result = {
  error: string | null;
  skipDocsCalls: number;
  buildNumbers: string[];
  versions: string[];
  metadataChanged: boolean;
  builds: Record<string, unknown>[];
  tests: Record<string, unknown>[];
  lintCalls: number;
};

// Execute the actual lane bodies and before_all hook. Only external Fastlane actions are stubbed;
// increment actions write fixture metadata so an accidental validation bump is observable on disk.
function runLane(name: string, options: Record<string, unknown> = {}, failure?: string): Result {
  const fastfile = readFileSync(fastfilePath, 'utf8');
  const hook = fastfile.match(/ {2}before_all do[^\n]*\n[\s\S]*?\n {2}end/)?.[0];
  expect(hook).toBeDefined();
  const lanes = ['lint', 'build', 'build_check', 'ci_ios', 'ci_test_unit', 'build_dev'].map(
    (lane) => {
      const body = fastfile.match(
        new RegExp(' {2}lane :' + lane + ' do[^\\n]*\\n[\\s\\S]*?\\n {2}end'),
      )?.[0];
      expect(body, lane).toBeDefined();
      return body;
    },
  );
  const directory = mkdtempSync(`${tmpdir()}/lyb-fastlane-validation-`);
  const sourcePath = `${directory}/lanes.rb`;
  mkdirSync(`${directory}/fastlane`);
  mkdirSync(`${directory}/LogYourBody.xcodeproj`);
  writeFileSync(
    sourcePath,
    ['scheme = "LogYourBody"', 'project = "LogYourBody.xcodeproj"', hook, ...lanes].join('\n'),
  );
  try {
    return JSON.parse(
      execFileSync(
        'ruby',
        [
          '-rjson',
          '-e',
          String.raw`
module UI
  def self.message(*); end
  def self.header(*); end
  def self.important(*); end
  def self.user_error!(message); raise message; end
end
module Actions
  def self.lane_context; {}; end
end
$lanes = {}
$skip_docs_calls = 0
$build_numbers = []
$versions = []
$builds = []
$tests = []
$lint_calls = 0
$failure = ARGV.fetch(3)
$metadata = File.expand_path("../LogYourBody.xcodeproj/project.pbxproj", Dir.pwd)
File.write($metadata, "original version and build")
def before_all(&block); $before_all = block; end
def lane(name, &block)
  $lanes[name] = block
  define_singleton_method(name) { |options = {}| $lanes.fetch(name).call(options) }
end
def skip_docs; $skip_docs_calls += 1; end
def setup_ci; end
def swiftlint(**options)
  $lint_calls += 1
  raise "lint failed" if $failure == "lint"
end
def increment_build_number(build_number:, **)
  $build_numbers << build_number
  File.write($metadata, "build #{build_number}")
end
def increment_version_number(version_number:, **)
  $versions << version_number
  File.write($metadata, "version #{version_number}")
end
def get_version_number(**); "1.0"; end
def get_build_number(**); "123"; end
def clean_build_artifacts; end
def build_app(options)
  $builds << options
  raise "build failed" if $failure == "build"
end
def run_tests(**options)
  $tests << options
  raise "tests failed" if $failure == "tests"
end
load ARGV.fetch(0)
error = nil
begin
  name = ARGV.fetch(1).to_sym
  $before_all.call(name)
  $lanes.fetch(name).call(JSON.parse(ARGV.fetch(2), symbolize_names: true))
rescue => exception
  error = exception.message
end
puts JSON.generate(error: error, skipDocsCalls: $skip_docs_calls,
  buildNumbers: $build_numbers, versions: $versions,
  metadataChanged: File.read($metadata) != "original version and build",
  builds: $builds, tests: $tests, lintCalls: $lint_calls)
`,
          sourcePath,
          name,
          JSON.stringify(options),
          failure ?? '',
        ],
        {
          cwd: `${directory}/fastlane`,
          encoding: 'utf8',
          timeout: 10_000,
          env: { ...process.env, CI: 'true' },
        },
      ),
    ) as Result;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function expectCleanValidation(result: Result) {
  expect(result.skipDocsCalls).toBe(1);
  expect(result.buildNumbers).toEqual([]);
  expect(result.versions).toEqual([]);
  expect(result.metadataChanged).toBe(false);
}

describe('Fastlane validation source preservation', () => {
  it.each(['ci_ios', 'build_check'])(
    '%s compiles without changing tracked metadata or docs',
    (lane) => {
      const result = runLane(lane);
      expectCleanValidation(result);
      expect(result.error).toBeNull();
      expect(result.builds).toHaveLength(1);
      expect(result.builds[0]).toMatchObject({
        configuration: 'Debug',
        skip_archive: true,
        skip_codesigning: true,
        clean: false,
      });
      expect(result.lintCalls).toBe(lane === 'ci_ios' ? 1 : 0);
    },
  );

  it('ci_test_unit keeps coverage enabled without changing metadata or requesting docs', () => {
    const result = runLane('ci_test_unit', { destination: 'platform=iOS Simulator,id=fixture' });
    expectCleanValidation(result);
    expect(result.error).toBeNull();
    expect(result.builds).toEqual([]);
    expect(result.tests).toEqual([
      expect.objectContaining({
        scheme: 'LogYourBodyTiers',
        testplan: 'Unit',
        code_coverage: true,
        result_bundle: true,
        destination: 'platform=iOS Simulator,id=fixture',
      }),
    ]);
  });

  it.each([
    ['ci_ios', 'lint', 'lint failed'],
    ['build_check', 'build', 'build failed'],
    ['ci_test_unit', 'tests', 'tests failed'],
  ])('%s preserves its %s failure and clean source', (lane, failure, message) => {
    const result = runLane(lane, {}, failure);
    expectCleanValidation(result);
    expect(result.error).toBe(message);
    if (failure === 'lint') expect(result.builds).toEqual([]);
  });

  it('release builds still generate a timestamp build number by default', () => {
    const result = runLane('build', { configuration: 'Release', export_method: 'app-store' });
    expect(result.error).toBeNull();
    expect(result.skipDocsCalls).toBe(0);
    expect(result.buildNumbers).toEqual([expect.stringMatching(/^\d{14}$/)]);
    expect(result.metadataChanged).toBe(true);
    expect(result.builds[0]).toMatchObject({
      configuration: 'Release',
      export_method: 'app-store',
    });
  });

  it('release builds preserve explicit build and marketing version bumps', () => {
    const result = runLane('build', {
      configuration: 'Release',
      export_method: 'app-store',
      build_number: '20261014230000',
      version_number: '2.3.4',
      skip_build_number_increment: false,
    });
    expect(result.error).toBeNull();
    expect(result.skipDocsCalls).toBe(0);
    expect(result.buildNumbers).toEqual(['20261014230000']);
    expect(result.versions).toEqual(['2.3.4']);
    expect(result.metadataChanged).toBe(true);
  });

  it('ordinary development builds retain their existing build number behavior', () => {
    const result = runLane('build_dev');
    expect(result.error).toBeNull();
    expect(result.skipDocsCalls).toBe(0);
    expect(result.buildNumbers).toEqual([expect.stringMatching(/^\d{14}$/)]);
    expect(result.metadataChanged).toBe(true);
  });
});
