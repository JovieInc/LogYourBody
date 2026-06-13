#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
PLATFORM = ENV.fetch("APP_STORE_PLATFORM", "IOS")

REVIEW_STATES = %w[
  READY_FOR_REVIEW
  WAITING_FOR_REVIEW
  IN_REVIEW
  PENDING_APPLE_RELEASE
  PROCESSING_FOR_DISTRIBUTION
  PROCESSING_FOR_APP_STORE
].freeze

SUCCESS_STATES = %w[
  READY_FOR_SALE
  PREORDER_READY_FOR_SALE
].freeze

FAILURE_STATES = %w[
  DEVELOPER_REJECTED
  METADATA_REJECTED
  REJECTED
  PENDING_CONTRACT
].freeze

def fail_with(message)
  warn "::error::#{message}"
  exit 1
end

def warn_with(message)
  warn "::warning::#{message}"
end

def api_key
  path = ENV.fetch("APP_STORE_CONNECT_API_KEY_PATH", "fastlane/api_key.json")
  JSON.parse(File.read(path))
rescue KeyError
  fail_with("APP_STORE_CONNECT_API_KEY_PATH is required")
rescue Errno::ENOENT
  fail_with("App Store Connect API key file not found")
rescue JSON::ParserError => e
  fail_with("App Store Connect API key file is invalid JSON: #{e.message}")
end

def bearer_token
  key = api_key
  private_key = OpenSSL::PKey::EC.new(key.fetch("key"))
  payload = {
    iss: key.fetch("issuer_id"),
    exp: Time.now.to_i + key.fetch("duration", 1200).to_i,
    aud: "appstoreconnect-v1"
  }
  headers = {
    kid: key.fetch("key_id"),
    typ: "JWT"
  }

  JWT.encode(payload, private_key, "ES256", headers)
rescue KeyError => e
  fail_with("App Store Connect API key is missing #{e.key}")
rescue OpenSSL::PKey::ECError => e
  fail_with("App Store Connect private key is invalid: #{e.message}")
end

def request(method, path, token, body: nil)
  uri = URI("#{API_BASE}#{path}")
  request_class = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post
  }.fetch(method)

  req = request_class.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  [response.code.to_i, response.body.empty? ? {} : JSON.parse(response.body)]
rescue JSON::ParserError => e
  fail_with("App Store Connect returned invalid JSON for #{path}: #{e.message}")
end

def expect(method, path, token, body: nil, expected: [200])
  status, parsed = request(method, path, token, body: body)
  return parsed if expected.include?(status)

  fail_with("App Store Connect #{method.upcase} #{path} returned #{status}: #{JSON.pretty_generate(parsed)}")
end

def app_by_bundle_id(token)
  bundle_id = ENV.fetch("APP_IDENTIFIER", "com.logyourbody.app")
  query = URI.encode_www_form("filter[bundleId]" => bundle_id, "limit" => "1")
  response = expect(:get, "/v1/apps?#{query}", token)
  app = response.fetch("data", []).first
  fail_with("No App Store Connect app found for bundle ID #{bundle_id}") unless app

  [app.fetch("id"), bundle_id]
end

def app_id(token)
  configured = ENV["APP_STORE_APP_ID"].to_s.strip
  unless configured.empty?
    query = URI.encode_www_form("fields[apps]" => "bundleId")
    status, parsed = request(:get, "/v1/apps/#{configured}?#{query}", token)
    return configured if status == 200

    unless status == 404
      fail_with("App Store Connect GET /v1/apps/#{configured} returned #{status}: #{JSON.pretty_generate(parsed)}")
    end

    resolved_id, bundle_id = app_by_bundle_id(token)
    warn_with("Configured APP_STORE_APP_ID #{configured} was not found in App Store Connect; using app #{resolved_id} resolved from bundle ID #{bundle_id}.")
    return resolved_id
  end

  app_by_bundle_id(token).first
end

def app_store_versions(token, app_id)
  query = URI.encode_www_form(
    "filter[platform]" => PLATFORM,
    "fields[appStoreVersions]" => "versionString,appVersionState,platform",
    "limit" => "20"
  )
  response = expect(:get, "/v1/apps/#{app_id}/appStoreVersions?#{query}", token)
  response.fetch("data", [])
end

def selected_version(versions)
  requested_version = ENV["APP_VERSION"].to_s.strip
  if requested_version.empty?
    versions.find { |version| version.dig("attributes", "appVersionState") == "PENDING_DEVELOPER_RELEASE" } ||
      versions.find { |version| REVIEW_STATES.include?(version.dig("attributes", "appVersionState").to_s) } ||
      versions.first
  else
    versions.find { |version| version.dig("attributes", "versionString") == requested_version }
  end
end

def request_release(token, app_store_version_id)
  body = {
    data: {
      type: "appStoreVersionReleaseRequests",
      relationships: {
        appStoreVersion: {
          data: {
            type: "appStoreVersions",
            id: app_store_version_id
          }
        }
      }
    }
  }

  expect(:post, "/v1/appStoreVersionReleaseRequests", token, body: body, expected: [201])
end

token = bearer_token
id = app_id(token)
version = selected_version(app_store_versions(token, id))

if version.nil?
  app_version = ENV["APP_VERSION"].to_s.strip
  fail_with(app_version.empty? ? "No App Store versions found for #{id}" : "App Store version #{app_version} was not found for #{id}")
end

version_id = version.fetch("id")
version_string = version.dig("attributes", "versionString")
state = version.dig("attributes", "appVersionState").to_s

case state
when "PENDING_DEVELOPER_RELEASE"
  request_release(token, version_id)
  puts "Released approved App Store version #{version_string} (#{version_id})."
when *SUCCESS_STATES
  puts "App Store version #{version_string} is already #{state}; no release action needed."
when *REVIEW_STATES
  puts "App Store version #{version_string} is #{state}; waiting for Apple approval."
when *FAILURE_STATES
  fail_with("App Store version #{version_string} is #{state}; release needs remediation.")
else
  warn_with("App Store version #{version_string} is #{state}; no release action taken.")
end
