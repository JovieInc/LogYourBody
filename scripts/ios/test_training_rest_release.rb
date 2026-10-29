# frozen_string_literal: true

# Execute the real release lane, instrumenting only external Fastlane actions.
# This proves the archive signs and exports only the app profile while the
# unprovisioned rest-timer extension is excluded from the archive (LYB-310).
require 'json'

root = File.expand_path('../..', __dir__)
release_file = ARGV[0] || File.join(root, 'apps/ios/fastlane/Fastfile.release')
LANES = {}
SIGNING = []
BUILDS = []
PROVISIONING = []

module UI
  def self.method_missing(*) = nil
  def self.respond_to_missing?(*) = true
end
module SharedValues
  XCODEBUILD_ARCHIVE = :archive
end
def desc(*) = nil
def lane(name, &body) = LANES[name] = body
def project = 'LogYourBody.xcodeproj'
def scheme = 'LogYourBody'
def lane_context = {}
def update_code_signing_settings(**options) = SIGNING << options
def build_app(**options) = BUILDS << options
def setup_provisioning(**options) = PROVISIONING << options
def sentry_upload_symbols(*) = nil

load release_file

# The real exclusion helper needs the xcodeproj gem; record the invocation.
REST_TIMER_EXCLUSIONS = []
def exclude_rest_timer_extension_from_release_archive
  REST_TIMER_EXCLUSIONS << true
end

ENV['APP_IDENTIFIER'] = 'com.logyourbody.app'
ENV['APPLE_TEAM_ID'] = 'fixture-team'
ENV['MATCH_GIT_URL'] = 'fixture-repository'
ENV['MATCH_PASSWORD'] = 'fixture-password'

2.times do |index|
  SIGNING.clear
  BUILDS.clear
  PROVISIONING.clear
  REST_TIMER_EXCLUSIONS.clear
  app_profile = index.zero? ? nil : 'installed-app-profile'
  rest_profile = index.zero? ? nil : 'installed-extension-profile'
  ENV['PROVISIONING_PROFILE_SPECIFIER'] = app_profile
  ENV['REST_TIMER_PROVISIONING_PROFILE_SPECIFIER'] = rest_profile
  LANES.fetch(:build_release).call
  # LYB-310: the rest-timer extension has no App Store profile, so the release
  # lane signs and exports only the app and excludes the extension from the
  # archive. The env profile specifiers are still read but the extension
  # mapping must not reach signing or export options.
  expected = {
    'com.logyourbody.app' => app_profile || 'match AppStore com.logyourbody.app 1780400349'
  }
  build = BUILDS.fetch(0)
  raise 'Missing app export profile' unless build[:export_options][:provisioningProfiles] == expected
  raise 'Release export still requests the unprovisioned rest-timer extension' if build[:export_options][:provisioningProfiles].key?('com.logyourbody.app.rest-timer')
  raise 'Archive applies a profile override to every executable' if build[:xcargs].include?('PROVISIONING_PROFILE')
  raise 'Provisioning must remain readonly' unless PROVISIONING == [{ type: 'appstore', readonly: true }]
  raise 'Release archive did not exclude the rest-timer extension' unless REST_TIMER_EXCLUSIONS == [true]
  raise 'Expected one target-specific signing update' unless SIGNING.size == 1
  SIGNING.each do |signing|
    identifier = signing.fetch(:bundle_identifier)
    raise 'Signing update mentions the rest-timer extension' if identifier.end_with?('.rest-timer')
    raise 'Signing update affects other targets' unless signing[:targets] == ['LogYourBody']
    raise 'Wrong target profile' unless signing[:profile_name] == expected.fetch(identifier)
    raise 'Signing policy was weakened' unless signing[:use_automatic_signing] == false
  end
end
puts JSON.generate(cases: 2, result: 'Release archive signs only the app while the rest-timer extension lacks an App Store profile')
