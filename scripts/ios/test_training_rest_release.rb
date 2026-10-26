# frozen_string_literal: true

# Execute the real release lane, instrumenting only external Fastlane actions.
# This proves the archive receives separate signing identities for both executables.
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
ENV['APP_IDENTIFIER'] = 'com.logyourbody.app'
ENV['APPLE_TEAM_ID'] = 'fixture-team'
ENV['MATCH_GIT_URL'] = 'fixture-repository'
ENV['MATCH_PASSWORD'] = 'fixture-password'

2.times do |index|
  SIGNING.clear
  BUILDS.clear
  PROVISIONING.clear
  app_profile = index.zero? ? nil : 'installed-app-profile'
  rest_profile = index.zero? ? nil : 'installed-extension-profile'
  ENV['PROVISIONING_PROFILE_SPECIFIER'] = app_profile
  ENV['REST_TIMER_PROVISIONING_PROFILE_SPECIFIER'] = rest_profile
  LANES.fetch(:build_release).call
  expected = {
    'com.logyourbody.app' => app_profile || 'match AppStore com.logyourbody.app 1780400349',
    'com.logyourbody.app.rest-timer' => rest_profile || 'match AppStore com.logyourbody.app.rest-timer'
  }
  build = BUILDS.fetch(0)
  raise 'Missing separate app and rest extension export profiles' unless build[:export_options][:provisioningProfiles] == expected
  raise 'Archive applies a profile override to every executable' if build[:xcargs].include?('PROVISIONING_PROFILE')
  raise 'Provisioning must remain readonly' unless PROVISIONING == [{ type: 'appstore', readonly: true }]
  raise 'Expected two target-specific signing updates' unless SIGNING.size == 2
  SIGNING.each do |signing|
    identifier = signing.fetch(:bundle_identifier)
    target = identifier.end_with?('.rest-timer') ? 'LogYourBodyRestTimer' : 'LogYourBody'
    raise 'Signing update affects other targets' unless signing[:targets] == [target]
    raise 'Wrong target profile' unless signing[:profile_name] == expected.fetch(identifier)
    raise 'Signing policy was weakened' unless signing[:use_automatic_signing] == false
  end
end
puts JSON.generate(cases: 2, result: 'App and rest extension use distinct target and export profiles')
