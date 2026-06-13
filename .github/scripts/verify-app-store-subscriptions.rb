#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
PLATFORM = ENV.fetch("APP_STORE_PLATFORM", "IOS")
DEFAULT_REQUIRED_PRODUCTS = %w[
  com.logyourbody.app.pro1.annual.3daytrial
  com.logyourbody.app.pro1.monthly.3daytrial
].freeze
DEFAULT_ALLOWED_STATES = %w[APPROVED].freeze

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

def request(method, path, token)
  uri = URI("#{API_BASE}#{path}")
  request_class = { get: Net::HTTP::Get }.fetch(method)
  req = request_class.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  [response.code.to_i, response.body.empty? ? {} : JSON.parse(response.body)]
rescue JSON::ParserError => e
  fail_with("App Store Connect returned invalid JSON for #{path}: #{e.message}")
end

def expect(method, path, token, expected: [200])
  status, parsed = request(method, path, token)
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

def required_products
  configured = ENV["APP_STORE_REQUIRED_SUBSCRIPTION_PRODUCTS"].to_s
  products = configured.split(",").map(&:strip).reject(&:empty?)
  products.empty? ? DEFAULT_REQUIRED_PRODUCTS : products
end

def allowed_states
  configured = ENV["APP_STORE_SUBSCRIPTION_ALLOWED_STATES"].to_s
  states = configured.split(",").map(&:strip).reject(&:empty?)
  states.empty? ? DEFAULT_ALLOWED_STATES : states
end

def subscription_groups(token, app_id)
  query = URI.encode_www_form(
    "fields[subscriptionGroups]" => "referenceName",
    "limit" => "200"
  )
  expect(:get, "/v1/apps/#{app_id}/subscriptionGroups?#{query}", token).fetch("data", [])
end

def subscriptions_for_group(token, group_id)
  query = URI.encode_www_form(
    "fields[subscriptions]" => "name,productId,state",
    "limit" => "200"
  )
  expect(:get, "/v1/subscriptionGroups/#{group_id}/subscriptions?#{query}", token).fetch("data", [])
end

def subscription_product_records(token, app_id)
  subscription_groups(token, app_id).flat_map do |group|
    subscriptions_for_group(token, group.fetch("id"))
  end
end

token = bearer_token
id = app_id(token)
required = required_products
allowed = allowed_states
records = subscription_product_records(token, id)

by_product_id = records.to_h do |record|
  attributes = record.fetch("attributes", {})
  [attributes["productId"].to_s, attributes]
end

missing = required.reject { |product_id| by_product_id.key?(product_id) }
unless missing.empty?
  available = by_product_id.keys.reject(&:empty?).sort
  fail_with("App Store Connect is missing required subscription products for app #{id}: #{missing.join(", ")}. Available products: #{available.join(", ")}")
end

invalid = required.filter_map do |product_id|
  attributes = by_product_id.fetch(product_id)
  state = attributes["state"].to_s
  next if allowed.include?(state)

  "#{product_id}=#{state.empty? ? "UNKNOWN" : state}"
end

unless invalid.empty?
  fail_with("App Store Connect subscription products are not in allowed states #{allowed.join(", ")}: #{invalid.join(", ")}")
end

puts "Verified App Store subscription products for app #{id}: #{required.map { |product_id| "#{product_id}=#{by_product_id.fetch(product_id)["state"]}" }.join(", ")}."
