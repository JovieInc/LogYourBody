# frozen_string_literal: true
# Executes the real release script; only remote HTTP and signing are replaced.
require "json"
require "net/http"
require "tmpdir"

$LOADED_FEATURES << "jwt.rb"
module JWT
  def self.encode(*) = "fixture-asc-token"
end
settings = JSON.parse(ARGV.fetch(0))
$requests = []
current = { "id" => "new", "attributes" => { "versionString" => "1.3.0", "appVersionState" => settings.fetch("state", "PENDING_DEVELOPER_RELEASE") } }
previous = { "id" => "old", "attributes" => { "versionString" => "1.2.0", "appVersionState" => "REPLACED_WITH_NEW_VERSION" } }
versions = [current, previous]
versions.reverse! if settings["reverse_versions"]
versions.delete(previous) if settings["no_previous"]
phase = { "id" => "phase-new", "attributes" => { "phasedReleaseState" => settings.fetch("phase", "INACTIVE") } }
fixture_dir = __dir__
http = Object.new
http.define_singleton_method(:request) do |req|
  uri = req.uri
  query = URI.decode_www_form(uri.query.to_s).to_h
  $requests << { method: req.method, host: uri.host, path: uri.path, query: URI.decode_www_form(uri.query.to_s), body: req.body && JSON.parse(req.body) }
  status = 200
  body = case [uri.host, req.method, uri.path]
         when ["api.appstoreconnect.apple.com", "GET", "/v1/apps/123"] then { data: { id: "123" } }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/apps/123/appStoreVersions"] then { data: versions }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/apps/123/reviewSubmissions"], ["api.appstoreconnect.apple.com", "GET", "/v1/reviewSubmissions"] then { data: [] }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/appStoreVersions/new/appStoreVersionPhasedRelease"] then status = 404 if settings["phase_404"]
           { data: settings["no_phase"] || settings["phase_404"] ? nil : phase }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/appStoreVersions/old/appStoreVersionPhasedRelease"] then { data: nil }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/appStoreVersions/new/build"] then status = 404 if settings["missing_build"]
           { data: { attributes: { version: "130" } } }
         when ["api.appstoreconnect.apple.com", "GET", "/v1/appStoreVersions/old/build"] then { data: { attributes: { version: "120" } } }
         when ["api.appstoreconnect.apple.com", "PATCH", "/v1/appStoreVersionPhasedReleases/phase-new"]
           status = settings.fetch("pause_status", 200)
           { data: phase.merge("attributes" => { "phasedReleaseState" => settings.fetch("pause_response", "PAUSED") }) }
         when ["api.appstoreconnect.apple.com", "POST", "/v1/appStoreVersionReleaseRequests"]
           status = 201
           {}
         when ["sentry.io", "GET", "/api/0/organizations/jovie/sessions/"]
           status = settings.fetch("sentry_status", 200)
           release = query.fetch("query").delete_prefix('release:"').delete_suffix('"')
           name = release == "ios-1.3.0 (130)" ? settings.fetch("fixture", "healthy") : settings.fetch("previous_fixture", "healthy")
           payload = JSON.parse(File.read(File.join(fixture_dir, "#{name}.json")))
           payload["groups"].each { |group| group["by"]["release"] = settings.fetch("response_release", release) }
           if settings["session_rate"] && release == "ios-1.3.0 (130)"
             payload.dig("groups", 0, "totals")["crash_free_rate(session)"] = settings["session_rate"]
           end
           if payload["groups"].any? && settings["null_rate"]
             payload.dig("groups", 0, "totals")["crash_free_rate(user)"] = nil
           end
           if payload["groups"].any? && settings["few_users"]
             payload.dig("groups", 0, "totals")["count_unique(user)"] = 1
           end
           payload["end"] = (Time.at((Time.now.to_i / 3600 + 1) * 3600).utc + (settings["stale"] ? -86_400 : 0) + (settings["future"] ? 7200 : 0)).iso8601
           payload
         when ["api.github.com", "GET", "/repos/fixture/repo/issues"]
           settings["issue_state"] ? [{ number: 42, title: "[LYB-139] App Store 1.3.0 release health", state: settings["issue_state"], html_url: "https://github.com/fixture/repo/issues/42" }] : []
         when ["api.github.com", "POST", "/repos/fixture/repo/issues"], ["api.github.com", "PATCH", "/repos/fixture/repo/issues/42"]
           status = settings.fetch("issue_status", req.method == "POST" ? 201 : 200)
           { html_url: "https://github.com/fixture/repo/issues/42" }
         else raise "Unexpected fixture request #{req.method} #{uri}"
         end
  Struct.new(:code, :body).new(status.to_s, JSON.generate(body))
end
Net::HTTP.define_singleton_method(:start) { |*args, **kwargs, &block| block.call(http) }

Dir.mktmpdir("lyb-health-") do |directory|
  key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
  File.write("#{directory}/key.json", JSON.generate(key: key, issuer_id: "fixture", key_id: "fixture"))
  ENV.update("APP_STORE_CONNECT_API_KEY_PATH" => "#{directory}/key.json", "GITHUB_STEP_SUMMARY" => "#{directory}/summary.md", "APP_STORE_APP_ID" => "123", "APP_VERSION" => settings.fetch("app_version", "1.3.0"), "SENTRY_AUTH_TOKEN" => "fixture-secret", "SENTRY_ORG" => "jovie", "SENTRY_PROJECT" => "log-your-body-ios", "RELEASE_HEALTH_MIN_CRASH_FREE_PERCENT" => "99.5", "RELEASE_HEALTH_MIN_SESSIONS" => "100", "RELEASE_HEALTH_MIN_USERS" => "20", "GH_TOKEN" => "fixture-gh-secret", "GITHUB_REPOSITORY" => "fixture/repo", "GITHUB_RUN_ID" => "1")
  ENV.delete("SENTRY_AUTH_TOKEN") if settings["missing_token"]
  ENV["RELEASE_HEALTH_MAX_REGRESSION_PP"] = settings.fetch("regression_pp", "0.5").to_s
  exit_code = 0
  begin
    load ENV.fetch("RELEASE_SCRIPT", File.expand_path("../../release-approved-app-store-version.rb", __dir__))
  rescue SystemExit => error
    exit_code = error.status
  end
  puts JSON.generate(exit_code: exit_code, requests: $requests, summary: File.exist?(ENV["GITHUB_STEP_SUMMARY"]) ? File.read(ENV["GITHUB_STEP_SUMMARY"]) : "")
end
