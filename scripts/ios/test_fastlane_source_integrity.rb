# frozen_string_literal: true
# Execute the actual Fastfile lane bodies; build_app is instrumented, not Xcode.
require 'coverage'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'
require 'shellwords'

ROOT = File.expand_path('../..', __dir__)
FASTFILE = File.join(ROOT, 'apps/ios/fastlane/Fastfile')
WORKFLOW = File.join(ROOT, '.github/workflows/ios-unit.yml')
LANES = {}
STATE = { actions: [], version: '100', fail_build: false }
module UI
  def self.method_missing(*) = nil
  def self.respond_to_missing?(*) = true
end
module LaneHarness
  def fastlane_version(*) = nil
  def default_platform(*) = nil
  def platform(*) = yield
  def desc(*) = nil
  def before_all(*) = nil
  def error(*) = nil
  def lane(name, &body) = LANES[name] = body
  def private_lane(name, &body) = lane(name, &body)
  def method_missing(name, *args, **kwargs)
    if LANES.key?(name)
      return LANES.fetch(name).call({}) if args.empty? && kwargs.empty?
      return LANES.fetch(name).call(*args, **kwargs)
    end
    case name
    when :get_version_number then '1.2.0'
    when :get_build_number then STATE[:version]
    when :increment_build_number
      values = kwargs.empty? ? args.fetch(0) : kwargs
      STATE[:version] = values.fetch(:build_number).to_s
      File.write(STATE.fetch(:version_file), STATE[:version])
      STATE[:actions] << name
    when :increment_version_number, :clean_build_artifacts, :swiftlint
      STATE[:actions] << name
    when :build_app
      STATE[:actions] << name
      STATE[:build_options] = kwargs.empty? ? args.fetch(0) : kwargs
      raise 'instrumented build failure' if STATE[:fail_build]
    else
      raise NoMethodError, "Uninstrumented Fastlane action: #{name}"
    end
  end
  def respond_to_missing?(name, *) = LANES.key?(name) || super
end
extend LaneHarness
def check(condition, message)
  raise message unless condition
end
Coverage.start(lines: true, branches: true)
load FASTFILE
checks = 0
Dir.mktmpdir('lyb-fastlane-version-') do |dir|
  STATE[:version_file] = File.join(dir, 'tracked-build-version')
  reset = lambda do
    STATE[:version] = '100'
    STATE[:actions] = []
    STATE[:fail_build] = false
    File.write(STATE[:version_file], '100')
  end
  reset.call
  ci_ios
  check(File.read(STATE[:version_file]) == '100', 'ci_ios changed tracked build identity')
  check(!STATE[:actions].include?(:increment_build_number), 'compile check invoked version action')
  check(STATE[:actions].include?(:build_app), 'compile check did not reach build_app')
  check(STATE[:build_options][:skip_archive] == true, 'compile check stopped using simulator build')
  checks += 1

  [nil, false, 'true'].each do |preserve|
    reset.call
    options = { clean_artifacts: false }
    options[:skip_build_number_increment] = preserve unless preserve.nil?
    build(options)
    check(File.read(STATE[:version_file]).match?(/\A\d{14}\z/), 'normal build lost timestamp versioning')
    check(STATE[:actions].include?(:increment_build_number), 'normal build skipped version action')
    checks += 1
  end
  reset.call
  build(build_number: '234', clean_artifacts: false)
  check(File.read(STATE[:version_file]) == '234', 'explicit release build number was ignored')
  checks += 1

  reset.call
  STATE[:fail_build] = true
  begin
    ci_ios
    raise 'compile failure was swallowed'
  rescue RuntimeError => e
    raise unless e.message == 'instrumented build failure'
  end
  check(File.read(STATE[:version_file]) == '100', 'failed compile mutated build identity')
  checks += 1
end

workflow = YAML.safe_load(File.read(WORKFLOW), aliases: true)
job = workflow.fetch('jobs').fetch('unit')
check(job.fetch('env').fetch('FASTLANE_SKIP_DOCS').to_s == 'true',
      'Both real Fastlane invocations require the supported docs control')
step = job.fetch('steps').find { |entry| entry['name'] == 'Unit-tier tests and native coverage ratchet' }
command = step.fetch('run')
python = Open3.capture2('python3', '-c', 'import sys; print(sys.executable)').first.strip
selector = { 'scheme' => 'LogYourBodyTiers', 'onlyTesting' => nil, 'testPlan' => 'Unit' }
quality = { 'scheme' => 'LogYourBody', 'onlyTesting' => 'LogYourBodyTests', 'testPlan' => nil }
required = 'RiskTests/testWriteAdmission()'
[ ['clean', 0, false], ['post-unit-mutation', 65, true], ['native-failure', 23, true], ['resolver-failure', 17, false] ].each do |mode, expected, dirty|
  Dir.mktmpdir('lyb-unit-workflow-') do |dir|
    FileUtils.mkdir_p(File.join(dir, 'apps/ios/LogYourBody'))
    FileUtils.mkdir_p(File.join(dir, 'scripts/ios'))
    FileUtils.mkdir_p(File.join(dir, 'bin'))
    File.write(File.join(dir, 'apps/ios/LogYourBody/Probe.swift'), 'let current = 1\n')
    FileUtils.cp(File.join(ROOT, 'scripts/ios/native-coverage-ratchet.py'), File.join(dir, 'scripts/ios'))
    baseline = {
      schemaVersion: 1, target: 'LogYourBody.app', longTermTargetPercent: 70,
      appSourceFiles: ['Probe.swift'],
      profiles: {
        'quality-unit' => { selector: quality, coveredLines: 1, executableLines: 2, requiredTests: [required] },
        'unit-tier' => { selector: selector, coveredLines: 1, executableLines: 2, requiredTests: [required] }
      }
    }
    File.write(File.join(dir, 'scripts/ios/native-coverage-baseline.json'), JSON.generate(baseline))
    File.write(File.join(dir, 'scripts/ios/resolve-simulator-destination.sh'), <<~SH)
      if [[ "$TEST_MODE" == resolver-failure ]]; then echo "instrumented resolver failure" >&2; exit 17; fi
      echo 'platform=iOS Simulator,id=fixture'
    SH
    # Only the native executable/exporter is controlled. The actual YAML shell,
    # git source receipts and production ratchet run unchanged.
    File.write(File.join(dir, 'bin/bundle'), <<~SH)
      #!/bin/bash
      echo "instrumented Unit invocation $TEST_MODE"
      for argument in "$@"; do
        case "$argument" in output_directory:*) output="${argument#output_directory:}";; esac
      done
      mkdir -p "$output/current.xcresult"
      if [[ "$TEST_MODE" != clean ]]; then
        echo 'let changedAfterUnitEntry = 2' >> "$GITHUB_WORKSPACE/apps/ios/LogYourBody/Probe.swift"
      fi
      [[ "$TEST_MODE" != native-failure ]] || exit 23
    SH
    exporter = <<~PY
      import sys,pathlib,json,hashlib
      bundle=pathlib.Path(sys.argv[sys.argv.index('--bundle')+1]); root=bundle.parent
      report={'targets':[{'name':'LogYourBody.app','coveredLines':1,'executableLines':2,'lineCoverage':.5,
        'files':[{'path':str(pathlib.Path.cwd()/'apps/ios/LogYourBody/Probe.swift'),'coveredLines':1,'executableLines':2}]}]}
      raw=json.dumps(report).encode(); bundle.with_suffix('.coverage.json').write_bytes(raw)
      receipt={'status':'passed','evidenceKind':'unit_tests','sourceRevision':(root/'source-revision.txt').read_text().strip(),
        'sourcePatchSha256':hashlib.sha256((root/'source-working-tree.patch').read_bytes()).hexdigest(),
        'coverageSha256':hashlib.sha256(raw).hexdigest(),'tests':[{'identifier':'#{required}','result':'Passed'}]}
      bundle.with_suffix('.evidence.json').write_text(json.dumps(receipt))
    PY
    File.write(File.join(dir, 'exporter.py'), exporter)
    File.write(File.join(dir, 'bin/python3'), <<~SH)
      #!/bin/bash
      if [[ "$1" == scripts/ios/launch-quality-evidence.py ]]; then
        shift
        exec #{Shellwords.escape(python)} "$GITHUB_WORKSPACE/exporter.py" "$@"
      fi
      exec #{Shellwords.escape(python)} "$@"
    SH
    FileUtils.chmod(0o755, [File.join(dir, 'bin/bundle'), File.join(dir, 'bin/python3')])
    ['git init -q', 'git add .', 'git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture'].each do |cmd|
      _, status = Open3.capture2e(cmd, chdir: dir)
      check(status.success?, 'fixture Git preparation failed')
    end
    sha = Open3.capture2('git', 'rev-parse', 'HEAD', chdir: dir).first.strip
    env = { 'GITHUB_WORKSPACE' => dir, 'GITHUB_RUN_ID' => 'fixture', 'GITHUB_RUN_ATTEMPT' => '1',
            'GITHUB_ENV' => File.join(dir, 'github-env'), 'BASE_SHA' => sha, 'TEST_MODE' => mode,
            'PATH' => File.join(dir, 'bin') + ':' + ENV.fetch('PATH'),
            'FASTLANE_SKIP_DOCS' => job.fetch('env').fetch('FASTLANE_SKIP_DOCS').to_s }
    output, status = Open3.capture2e(env, 'bash', '-e', '-o', 'pipefail', '-c', command, chdir: dir)
    check(status.exitstatus == expected, "#{mode}: expected exit#{expected}, got#{status.exitstatus}: #{output}")
    results = File.join(dir, 'apps/ios/test_results/unit-tier/fixture-1')
    check(File.binread(File.join(results, 'source-before-unit.patch')).empty?,
          "#{mode}: fixture input was already dirty before the actual Unit command")
    patch = File.binread(File.join(results, 'source-working-tree.patch'))
    check(!patch.empty? == dirty, "#{mode}: post-test tracked mutation missing from source receipt")
    expected_log = mode == 'resolver-failure' ? 'instrumented resolver failure' : "instrumented Unit invocation #{mode}"
    check(File.read(File.join(results, 'unit-tier.log')).include?(expected_log),
          "#{mode}: native output was not preserved")
    if mode == 'resolver-failure'
      check(!File.read(File.join(results, 'unit-tier.log')).include?('instrumented Unit invocation'),
            'failed destination resolver fell through to native execution')
    end
    if mode == 'post-unit-mutation'
      check(output.include?('Dirty or unknown source patch'), 'post-unit dirty source did not reach the real ratchet')
    end
    if ['native-failure', 'resolver-failure'].include?(mode)
      check(!File.exist?(File.join(results, 'current.evidence.json')), 'failed native command was exported as passing')
    end
    checks += 1
  end
end
measured = Coverage.result.fetch(FASTFILE)
lines = File.readlines(FASTFILE)
guard = lines.index { |line| line.include?('if options[:skip_build_number_increment] != true') }
check(guard && measured.fetch(:lines).fetch(guard).to_i > 0, 'production version guard did not execute')
branches = measured.fetch(:branches).select { |location, _| location[2] == guard + 1 }
check(branches.length == 1 && branches.values.first.values.all? { |count| count > 0 },
      'both actual version guard branches must execute')
opt = lines.index { |line| line.include?('skip_build_number_increment: true') }
call_line = opt && lines[0..opt].rindex { |line| line.strip == 'build(' }
check(call_line && measured.fetch(:lines).fetch(call_line).to_i > 0, 'actual build_check call did not execute')
puts JSON.generate({ cases: checks, actualFastfileVersionGuardLine: guard + 1,
                     versionGuardBranchCounts: branches.values.first.values,
                     actualBuildCheckCallLine: call_line + 1,
                     nativeBuild: 'instrumented build_app; real native CI still required',
                     docsProof: 'workflow env checked; actual Fastlane docs control inspected separately; native clean patch still required' })
