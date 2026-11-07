# frozen_string_literal: true

# Print the bundle ids setup_provisioning passes to match for the release
# loop: type appstore, readonly true. The ids come from Fastfile.release.
# When that lane omits app_identifier, Matchfile's list is the fallback.
# This process must not receive signing secrets. It does not call Apple.

require 'json'

release_file = ARGV.fetch(0)
MATCH_CALLS = []

%w[MATCH_READONLY MATCH_FORCE_ENTERPRISE MATCH_TYPE APP_IDENTIFIER].each { |name| ENV.delete(name) }
# Any non-empty value selects the match branch. Not a URL: the lane only
# tests truthiness, and match itself is stubbed.
ENV['MATCH_GIT_URL'] = 'local-match'

module UI
  def self.user_error!(message) = raise(message.to_s)
  def self.method_missing(*) = nil
  def self.respond_to_missing?(*) = true
end

module SharedValues
  APP_STORE_CONNECT_API_KEY = :app_store_connect_api_key
end

LANES = {}
def desc(*) = nil
def lane(name, &body) = LANES[name] = body
def setup_app_store_connect_api(*) = nil
def match(params) = MATCH_CALLS << params
def lane_context = {}
def install_provisioning_profile(*) = nil
def validate_profile(*) = nil

def matchfile_identifiers(release_path)
  path = File.expand_path('Matchfile', File.dirname(release_path))
  return [] unless File.file?(path)

  text = File.read(path)
  listed = text.match(/app_identifier\s*\(\s*\[([^\]]*)\]/m)
  return [] unless listed

  listed[1].scan(/"([^"\r\n]+)"/).flatten
end

load release_file
LANES.fetch(:setup_provisioning).call({ type: 'appstore', readonly: true })
params = MATCH_CALLS.fetch(0)
raw = params[:app_identifier]
raw = matchfile_identifiers(release_file) if raw.nil?
ids = Array(raw).map(&:to_s)
if ids.empty? || ids.any? { |id| id.empty? || id.match?(/[\r\n\s]/) }
  warn 'release signing identifiers unreadable'
  exit 1
end
puts JSON.generate(ids)
