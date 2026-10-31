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
  versionLookups: Record<string, unknown>[];
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
$version_lookups = []
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
def get_version_number(**options)
  $version_lookups << options
  versions = { "LogYourBody" => "1.0", "LogYourBodyRestTimer" => "0.0" }
  raise "Could not retrieve target as fastlane runs in non-interactive mode" unless options[:target]
  versions.fetch(options[:target])
end
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
  versionLookups: $version_lookups,
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
  it.each(['LogYourBody', 'LogYourBodyTiers'])(
    'reads the app version without prompting when building scheme %s with an extension',
    (scheme) => {
      const result = runLane('build', { scheme, skip_build_number_increment: true });
      expect(result.error).toBeNull();
      expect(result.versionLookups).toEqual([
        {
          xcodeproj: expect.stringMatching(/\/LogYourBody\.xcodeproj$/),
          target: 'LogYourBody',
        },
      ]);
      expect(result.builds[0]).toMatchObject({ scheme });
    },
  );

  it('builds and embeds the rest Live Activity through the app target', () => {
    const script = fileURLToPath(
      new URL('../../../scripts/ios/test_training_rest_project.py', import.meta.url),
    );
    expect(execFileSync('python3', [script], { encoding: 'utf8' })).toContain(
      'project graph passed',
    );
  });
  it('rejects native test registrations lost or duplicated during project merges', () => {
    const script = fileURLToPath(
      new URL('../../../scripts/ios/test_training_rest_project.py', import.meta.url),
    );
    const project = readFileSync(
      new URL('../../../apps/ios/LogYourBody.xcodeproj/project.pbxproj', import.meta.url),
      'utf8',
    );
    const registrations = project
      .split('\n')
      .filter((line) => line.includes('ContextualHintRegistryTests.swift'));
    expect(registrations).toHaveLength(4);
    const directory = mkdtempSync(`${tmpdir()}/lyb-project-membership-`);
    try {
      const candidate = `${directory}/project.pbxproj`;
      for (const registration of registrations) {
        writeFileSync(candidate, project.replace(`${registration}\n`, ''));
        expect(() => execFileSync('python3', [script, candidate], { stdio: 'pipe' })).toThrow();
      }
      const source = registrations.find(
        (line) => line.includes('in Sources') && !line.includes('='),
      );
      expect(source).toBeDefined();
      writeFileSync(candidate, project.replace(`${source}\n`, `${source}\n${source}\n`));
      expect(() => execFileSync('python3', [script, candidate], { stdio: 'pipe' })).toThrow();
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
  it('rejects historical model rewrites and incomplete app/widget model graphs', () => {
    const script = fileURLToPath(
      new URL('../../../scripts/ios/test_training_rest_project.py', import.meta.url),
    );
    const proof = execFileSync(
      'python3',
      [
        '-c',
        `
import copy, hashlib, importlib.util, json, pathlib, plistlib, sys, tempfile
spec = importlib.util.spec_from_file_location('native_project_guard', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
old = b'<model><entity name="Measurement"/></model>\\n'
new = b'<model><entity name="Measurement"/><entity name="DatedOutcome"/></model>\\n'
locked = {name: hashlib.sha256(data).hexdigest() for name, data in [
    ('LogYourBodyV5.xcdatamodel', old), ('LogYourBodyV6.xcdatamodel', new)]}
project = {'objects': {
    'v5a': {'path': 'LogYourBodyV5.xcdatamodel'}, 'v5b': {'path': 'LogYourBodyV5.xcdatamodel'},
    'v6a': {'path': 'LogYourBodyV6.xcdatamodel'}, 'v6b': {'path': 'LogYourBodyV6.xcdatamodel'},
    'app': {'isa': 'XCVersionGroup', 'path': 'LogYourBody.xcdatamodeld',
            'children': ['v5a', 'v6a'], 'currentVersion': 'v6a'},
    'widget': {'isa': 'XCVersionGroup', 'path': 'LogYourBody.xcdatamodeld',
               'children': ['v5b', 'v6b'], 'currentVersion': 'v6b'}}}
failures = ['rewritten-history', 'missing-history', 'unreviewed-version', 'unregistered-version',
            'duplicate-child', 'duplicate-path', 'wrong-widget-version', 'unregistered-current',
            'missing-current', 'missing-widget-group', 'symlink-history']
for name in ['positive', *failures]:
    with tempfile.TemporaryDirectory(prefix='lyb-model-contract-') as directory:
        root = pathlib.Path(directory) / 'LogYourBody.xcdatamodeld'
        root.mkdir()
        for version, data in [('LogYourBodyV5.xcdatamodel', old), ('LogYourBodyV6.xcdatamodel', new)]:
            (root / version).mkdir()
            (root / version / 'contents').write_bytes(data)
        current = root / '.xccurrentversion'
        current.write_bytes(plistlib.dumps({'_XCCurrentVersionName': 'LogYourBodyV6.xcdatamodel'}))
        candidate = copy.deepcopy(project)
        objects = candidate['objects']
        previous = root / 'LogYourBodyV5.xcdatamodel' / 'contents'
        if name == 'rewritten-history': previous.write_bytes(new)
        elif name == 'missing-history': previous.unlink()
        elif name == 'unreviewed-version':
            (root / 'LogYourBodyV7.xcdatamodel').mkdir()
            (root / 'LogYourBodyV7.xcdatamodel' / 'contents').write_bytes(new)
        elif name == 'unregistered-version': objects['app']['children'].remove('v5a')
        elif name == 'duplicate-child': objects['app']['children'].append('v6a')
        elif name == 'duplicate-path':
            objects['extra'] = {'path': 'LogYourBodyV6.xcdatamodel'}
            objects['app']['children'].append('extra')
        elif name == 'wrong-widget-version': objects['widget']['currentVersion'] = 'v5b'
        elif name == 'unregistered-current': objects['app']['currentVersion'] = 'v6b'
        elif name == 'missing-current':
            current.write_bytes(plistlib.dumps({'_XCCurrentVersionName': 'Missing.xcdatamodel'}))
        elif name == 'missing-widget-group': del objects['widget']
        elif name == 'symlink-history':
            copy_path = pathlib.Path(directory) / 'retained-history'
            copy_path.write_bytes(old)
            previous.unlink()
            previous.symlink_to(copy_path)
        try:
            module.check_model_versions(candidate, root, locked)
        except AssertionError:
            assert name != 'positive', 'Valid additive model must be accepted'
        else:
            assert name == 'positive', 'Unsafe model was accepted: ' + name
print(json.dumps({'accepted': 1, 'rejected': len(failures)}))
`,
        script,
      ],
      { encoding: 'utf8' },
    );
    expect(JSON.parse(proof)).toEqual({ accepted: 1, rejected: 11 });
  });
  it('signs the rest Live Activity extension separately in the real release lane', () => {
    const script = fileURLToPath(
      new URL('../../../scripts/ios/test_training_rest_release.rb', import.meta.url),
    );
    const result = JSON.parse(execFileSync('ruby', [script], { encoding: 'utf8' }));
    expect(result.cases).toBe(2);
  });
  it('resolves the rest-timer exclusion project path absolutely from the release Fastfile', () => {
    const script = fileURLToPath(
      new URL('../../../scripts/ios/test_rest_timer_exclusion_path.rb', import.meta.url),
    );
    const result = JSON.parse(
      execFileSync('ruby', [script], {
        encoding: 'utf8',
        // Measured at ~0.5s locally with all three tiers (LYB-346); the xcodeproj
        // gem load can stretch on slow CI runners. Kill a hung ruby rather than
        // wedging the vitest worker; the test timeout below is the outer bound.
        timeout: 15_000,
      }),
    );
    expect(result.failures).toEqual([]);
  }, 30_000);
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
