# frozen_string_literal: true

# LYB-310 regression control. Fastlane runs plain lane-body code with the cwd
# inside the fastlane/ folder; only actions are chdir'd up to the project
# folder (fastlane runner.rb execute_action). The release exclusion helper
# must therefore resolve the Xcode project absolutely from __dir__ so the
# release loop cannot fail only on main (run 40917899229). Tiers 1-2 need no
# gems; tier 3 needs the xcodeproj gem and executes the real helper against a
# temp copy of the checked-in project.

require 'fileutils'
require 'json'
require 'tmpdir'

ROOT = File.expand_path('../..', __dir__)
RELEASE_FILE = File.expand_path('apps/ios/fastlane/Fastfile.release', ROOT)
PROJECT_DIR = File.expand_path('../LogYourBody.xcodeproj', RELEASE_FILE)
FAILURES = []

def fail_unless(condition, message)
  FAILURES << message unless condition
end

# Tier 1: the helper must anchor its path on __dir__, never on the lane cwd.
source = File.read(RELEASE_FILE)
fail_unless(source.include?("File.expand_path('../LogYourBody.xcodeproj', __dir__)"),
            'exclusion helper must resolve the project from __dir__')
fail_unless(!source.match?(/File\.expand_path\('LogYourBody\.xcodeproj'\)/),
            'no cwd-relative project resolution may return')

# Tier 2: the resolved path must exist in a real checkout.
fail_unless(File.directory?(PROJECT_DIR), "resolved project missing: #{PROJECT_DIR}")

# Tier 3: execute the real helper against a temp copy of the project.
xcodeproj_available = begin
  require 'xcodeproj'
  true
rescue LoadError
  false
end

if xcodeproj_available
  LANES = {}
  module UI
    def self.method_missing(*) = nil
    def self.respond_to_missing?(*) = true
  end
  def desc(*) = nil
  def lane(name, &body) = LANES[name] = body
  def private_lane(name, &body) = lane(name, &body)
  def project = 'LogYourBody.xcodeproj'
  def scheme = 'LogYourBody'

  original = File.binread(File.join(PROJECT_DIR, 'project.pbxproj'))
  Dir.mktmpdir('lyb-rest-timer-exclusion-') do |dir|
    copy = File.join(dir, 'LogYourBody.xcodeproj')
    FileUtils.cp_r(PROJECT_DIR, copy)
    load RELEASE_FILE
    exclude_rest_timer_extension_from_release_archive(copy)
    stripped = Xcodeproj::Project.open(copy)
    app = stripped.targets.find { |target| target.name == 'LogYourBody' }
    extension = stripped.targets.find { |target| target.name == 'LogYourBodyRestTimer' }
    fail_unless(app, 'app target must survive the strip')
    fail_unless(extension, 'extension target must remain defined in the project')
    unless app.nil? || extension.nil?
      fail_unless(app.dependencies.none? { |dependency| dependency.target == extension },
                  'app must no longer depend on the extension')
      app.copy_files_build_phases.each do |phase|
        fail_unless(phase.files.none? { |file| file.display_name.to_s.include?('LogYourBodyRestTimer') },
                    "embed phase must not embed the extension: #{phase.name}")
      end
    end
  end
  fail_unless(File.binread(File.join(PROJECT_DIR, 'project.pbxproj')) == original,
              'the checked-in project must not be modified by the helper')
end

unless FAILURES.empty?
  warn FAILURES.join("\n")
  exit 1
end
puts JSON.generate(
  cases: xcodeproj_available ? 3 : 2,
  failures: FAILURES,
  result: 'release exclusion project path resolves and strips correctly'
)
