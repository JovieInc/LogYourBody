# frozen_string_literal: true

# LYB-338: a signing refresh that has to create a distribution certificate
# must create the same identity the release lanes and the Xcode project use.
# Fastlane cert (2.240, cert/lib/cert/runner.rb certificate_types), non-enterprise:
#   generate_apple_certs true  + distribution => DISTRIBUTION      => "Apple Distribution"
#   generate_apple_certs false + distribution => IOS_DISTRIBUTION  => "iOS Distribution"
# Readonly match installs the certificate already in the repo and refuses to
# create one. This executes the real lanes and only stubs external actions.
require 'json'

ROOT = File.expand_path('../..', __dir__)
FASTFILE = File.join(ROOT, 'apps/ios/fastlane/Fastfile')
PROJECT = File.join(ROOT, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj')
RUNBOOK = File.join(ROOT, 'docs/engineering/signing-expiry.md')
RELEASE_IDENTITY = 'Apple Distribution'
LEGACY_DISTRIBUTION_IDENTITY = 'iOS Distribution'

LANES = {}
MATCH_CALLS = []
SIGNING = []
BUILDS = []
cases = 0

module UI
  def self.message(*) = nil
  def self.important(*) = nil
  def self.error(*) = nil
  def self.success(*) = nil
  def self.header(*) = nil
  def self.user_error!(message) = raise(message.to_s)
  def self.method_missing(*) = nil
  def self.respond_to_missing?(*) = true
end

module SharedValues
  SIGH_NAME = :SIGH_NAME
  SIGH_UUID = :SIGH_UUID
  XCODEBUILD_ARCHIVE = :XCODEBUILD_ARCHIVE
  APP_STORE_CONNECT_API_KEY = :APP_STORE_CONNECT_API_KEY
end

module Actions
  def self.lane_context
    @lane_context ||= {}
  end
end

def lane_context = Actions.lane_context
def desc(*) = nil
def fastlane_version(*) = nil
def default_platform(*) = nil
def platform(*) = yield
def before_all(*) = nil
def error(*) = nil

def register_lane(name, body)
  LANES[name] = body
  define_singleton_method(name) do |positional = nil, **kwargs|
    args = positional.is_a?(Hash) ? positional.merge(kwargs) : kwargs
    body.arity.zero? ? body.call : body.call(args)
  end
end
def lane(name, &body) = register_lane(name, body)
def private_lane(name, &body) = register_lane(name, body)

def match(params) = MATCH_CALLS << params
def update_code_signing_settings(**options) = SIGNING << options
def build_app(options = nil, **kwargs) = BUILDS << (options.is_a?(Hash) ? options.merge(kwargs) : kwargs)
def sigh(**)
  lane_context[SharedValues::SIGH_NAME] = 'sigh-profile'
  lane_context[SharedValues::SIGH_UUID] = 'SIGH-UUID'
  'sigh-profile'
end
def upload_to_testflight(**) = nil
def clean_build_artifacts(*) = nil
def increment_build_number(**) = nil
def increment_version_number(**) = nil
def get_version_number(**) = '1.2.0'
def get_build_number(**) = '100'
def sh(*) = raise('unexpected shell call')

# cert/lib/cert/runner.rb maps this flag to the portal certificate type.
# The strings are the identities Xcode's CODE_SIGN_IDENTITY matches.
def portal_identity(generate_apple_certs:, type:)
  if type.to_s == 'development'
    generate_apple_certs ? 'Apple Development' : 'iOS Development'
  else
    generate_apple_certs ? RELEASE_IDENTITY : LEGACY_DISTRIBUTION_IDENTITY
  end
end

def check(condition, message)
  raise message unless condition
end

def reset_records
  MATCH_CALLS.clear
  SIGNING.clear
  BUILDS.clear
  lane_context.clear
end

def with_env(updates)
  saved = updates.keys.to_h { |key| [key, ENV[key]] }
  updates.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
  yield
ensure
  saved.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end

def created_distribution_identity(params, label)
  check(params[:readonly] == false, "#{label}: match stayed readonly, so it cannot create the certificate under test")
  check(params[:generate_apple_certs] == true, "#{label}: write-mode match would create #{LEGACY_DISTRIBUTION_IDENTITY}")
  identity = portal_identity(generate_apple_certs: params[:generate_apple_certs], type: params[:type])
  check(identity == RELEASE_IDENTITY, "#{label}: match creates #{identity}; release signing requests #{RELEASE_IDENTITY}")
  identity
end

original_env = ENV.to_h
original_project = File.binread(PROJECT)
begin
  %w[
    MATCH_READONLY MATCH_FORCE_ENTERPRISE MATCH_GIT_BRANCH
    APP_STORE_CONNECT_API_KEY_PATH APP_STORE_CONNECT_API_KEY
    APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID
    APP_STORE_CONNECT_API_KEY_ISSUER_ID
    CI GITHUB_ACTIONS SENTRY_AUTH_TOKEN
    PROVISIONING_PROFILE_SPECIFIER REST_TIMER_PROVISIONING_PROFILE_SPECIFIER
  ].each { |key| ENV.delete(key) }
  ENV['MATCH_GIT_URL'] = 'https://github.com/JovieInc/certificates.git'
  ENV['MATCH_PASSWORD'] = 'fixture-password'
  ENV['APPLE_TEAM_ID'] = 'fixture-team'
  ENV['APP_IDENTIFIER'] = 'com.logyourbody.app'

  check(portal_identity(generate_apple_certs: false, type: 'appstore') == LEGACY_DISTRIBUTION_IDENTITY,
        'legacy distribution mapping drifted')
  check(portal_identity(generate_apple_certs: true, type: 'appstore') == RELEASE_IDENTITY,
        'Apple Distribution mapping drifted')

  load FASTFILE
  define_singleton_method(:exclude_rest_timer_extension_from_release_archive) { |*| nil }
  define_singleton_method(:sentry_upload_symbols) { |*| nil }

  # Runbook step 2. This is the call that can mint a certificate.
  reset_records
  setup_provisioning(type: 'appstore', readonly: false, force: false)
  check(MATCH_CALLS.size == 1, 'renewal did not call match once')
  renewal = MATCH_CALLS.fetch(0)
  check(renewal[:type] == 'appstore', 'renewal changed the match profile type')
  check(renewal[:force] == false, 'renewal set match force and can revoke the current certificate')
  renewal_identity = created_distribution_identity(renewal, 'renewal')
  cases += 1

  # Public distribution lane used by operators beside the runbook command.
  reset_records
  setup_distribution
  check(MATCH_CALLS.size == 1, 'setup_distribution did not call match once')
  check(created_distribution_identity(MATCH_CALLS.fetch(0), 'setup_distribution') == renewal_identity,
        'setup_distribution creates a different certificate type than renewal')
  cases += 1

  # force still must not fall back to the legacy type when it creates a certificate.
  reset_records
  setup_provisioning(type: 'appstore', readonly: true, force: true)
  check(MATCH_CALLS.size == 1, 'forced refresh did not call match once')
  forced = MATCH_CALLS.fetch(0)
  check(forced[:force] == true, 'forced refresh dropped force')
  check(created_distribution_identity(forced, 'forced refresh') == renewal_identity,
        'forced refresh creates a different certificate type than renewal')
  cases += 1

  # The lane's own rescue text tells operators to export MATCH_READONLY=false.
  reset_records
  with_env('MATCH_READONLY' => 'false') do
    setup_provisioning(type: 'appstore')
  end
  check(MATCH_CALLS.size == 1, 'MATCH_READONLY=false did not call match once')
  check(created_distribution_identity(MATCH_CALLS.fetch(0), 'MATCH_READONLY=false') == renewal_identity,
        'MATCH_READONLY=false creates a different certificate type than renewal')
  cases += 1

  # Ad hoc uses the same distribution certificate as app store.
  reset_records
  setup_provisioning(type: 'adhoc', readonly: false, force: false)
  check(MATCH_CALLS.size == 1, 'adhoc refresh did not call match once')
  check(created_distribution_identity(MATCH_CALLS.fetch(0), 'adhoc') == renewal_identity,
        'adhoc refresh creates a different certificate type than app store')
  cases += 1

  # Development write mode requests the modern Apple Development certificate.
  reset_records
  setup_certificates
  check(MATCH_CALLS.size == 1, 'setup_certificates did not call match once')
  development = MATCH_CALLS.fetch(0)
  check(development[:readonly] == false, 'development setup stayed readonly')
  check(development[:type] == 'development', 'development setup changed type')
  check(portal_identity(generate_apple_certs: development[:generate_apple_certs], type: development[:type]) == 'Apple Development',
        'development setup would create a legacy iOS Development certificate')
  cases += 1

  # Step 1 and release syncs install stored material. They must not create.
  reset_records
  setup_provisioning(type: 'appstore', readonly: true, force: false)
  check(MATCH_CALLS == [{
    type: 'appstore',
    app_identifier: ['com.logyourbody.app'],
    readonly: true,
    git_url: 'https://github.com/JovieInc/certificates.git',
    git_branch: 'main',
    git_basic_authorization: nil,
    team_id: 'fixture-team',
    generate_apple_certs: false,
    skip_provisioning_profiles: false,
    platform: 'ios',
    verbose: true,
    force: false,
    force_for_new_devices: false
  }], 'readonly confirm changed match options')
  cases += 1

  reset_records
  build_release
  check(MATCH_CALLS.size == 1, 'release archive did not sync provisioning once')
  check(MATCH_CALLS.fetch(0)[:readonly] == true, 'release archive provisioning can create certificates')
  check(MATCH_CALLS.fetch(0)[:type] == 'appstore', 'release archive changed match type')
  release_identities = SIGNING.map { |signing| signing[:code_sign_identity] }
  check(release_identities == [RELEASE_IDENTITY], "build_release signs with #{release_identities.inspect}")
  check(release_identities.all? { |identity| identity == renewal_identity },
        'build_release identity differs from the certificate renewal creates')
  cases += 1

  reset_records
  lane_context[SharedValues::SIGH_UUID] = 'SIGH-UUID'
  lane_context[SharedValues::SIGH_NAME] = 'sigh-profile'
  build(configuration: 'Release', export_method: 'app-store', clean_artifacts: false, skip_build_number_increment: true)
  build_identities = SIGNING.map { |signing| signing[:code_sign_identity] }
  check(build_identities == [RELEASE_IDENTITY], "build lane signs with #{build_identities.inspect}")
  xcargs = BUILDS.fetch(0)[:xcargs].to_s
  check(xcargs.include?("CODE_SIGN_IDENTITY='#{RELEASE_IDENTITY}'"),
        'build lane xcargs request a different code sign identity')
  check(!xcargs.include?(LEGACY_DISTRIBUTION_IDENTITY), 'build lane xcargs request the legacy distribution identity')
  cases += 1

  reset_records
  alpha(clean_artifacts: false)
  alpha_identities = SIGNING.map { |signing| signing[:code_sign_identity] }
  check(alpha_identities.uniq == [RELEASE_IDENTITY], "alpha signs with #{alpha_identities.inspect}")
  check(alpha_identities.all? { |identity| identity == renewal_identity },
        'alpha identity differs from the certificate renewal creates')
  cases += 1

  project_identities = original_project.scan(/"?CODE_SIGN_IDENTITY(?:\[sdk=iphoneos\*\])?"?\s*=\s*"([^"]+)"/).flatten
  check(!project_identities.empty?, 'project has no CODE_SIGN_IDENTITY')
  check(project_identities.uniq == [RELEASE_IDENTITY],
        "project CODE_SIGN_IDENTITY is #{project_identities.uniq.inspect}")
  check(project_identities.all? { |identity| identity == renewal_identity },
        'project identity differs from the certificate renewal creates')
  check(File.binread(PROJECT) == original_project, 'the signing test modified the Xcode project')
  cases += 1

  runbook = File.read(RUNBOOK)
  refresh = runbook[/### 2\. Refresh with match.*?(?=### 3\.|\z)/m]
  check(refresh, 'runbook is missing the refresh step')
  check(refresh.include?('bundle exec fastlane setup_provisioning type:appstore readonly:false force:false'),
        'runbook refresh command changed')
  check(refresh.include?(RELEASE_IDENTITY), 'runbook does not name the Apple Distribution certificate renewal creates')
  check(refresh.include?('security find-identity -v -p codesigning'),
        'runbook does not say how to verify the installed identity before the next release')
  check(refresh.include?('Apple Distribution:'),
        'runbook does not say which common name to accept')
  cases += 1
ensure
  ENV.replace(original_env)
end

puts JSON.generate(cases: cases, identity: RELEASE_IDENTITY,
                   result: 'Renewal creates the Apple Distribution certificate release lanes and CODE_SIGN_IDENTITY use')
