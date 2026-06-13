#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
BASE_TERRITORY = ENV.fetch("APP_STORE_BASE_TERRITORY", "USA")
FREE_PRICE_PATTERN = /\A0(?:\.0+)?\z/

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

def request(method, path, token, body: nil, expected: [200])
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

  return [response.code.to_i, response.body.empty? ? {} : JSON.parse(response.body)]
rescue JSON::ParserError => e
  fail_with("App Store Connect returned invalid JSON for #{path}: #{e.message}")
end

def expect(method, path, token, body: nil, expected: [200])
  status, parsed = request(method, path, token, body: body, expected: expected)
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

def pricing_configured?(token, app_id)
  query = URI.encode_www_form(
    "include" => "manualPrices,automaticPrices",
    "limit[manualPrices]" => "1",
    "limit[automaticPrices]" => "1"
  )
  status, parsed = request(:get, "/v1/apps/#{app_id}/appPriceSchedule?#{query}", token)

  return false if status == 404
  fail_with("Unable to read app price schedule: #{JSON.pretty_generate(parsed)}") unless status == 200

  included = parsed.fetch("included", [])
  included.any? { |resource| resource["type"] == "appPrices" }
end

def free_price_point_id(token, app_id)
  query = URI.encode_www_form(
    "filter[territory]" => BASE_TERRITORY,
    "fields[appPricePoints]" => "customerPrice",
    "limit" => "200"
  )
  response = expect(:get, "/v1/apps/#{app_id}/appPricePoints?#{query}", token)
  price_point = response.fetch("data", []).find do |point|
    point.dig("attributes", "customerPrice").to_s.match?(FREE_PRICE_PATTERN)
  end
  fail_with("No free App Store price point found for #{BASE_TERRITORY}") unless price_point

  price_point.fetch("id")
end

def create_free_price_schedule(token, app_id, price_point_id)
  included_price_id = "${free-price-#{BASE_TERRITORY.downcase}}"
  body = {
    data: {
      type: "appPriceSchedules",
      attributes: {},
      relationships: {
        app: {
          data: {
            type: "apps",
            id: app_id
          }
        },
        manualPrices: {
          data: [
            {
              type: "appPrices",
              id: included_price_id
            }
          ]
        },
        baseTerritory: {
          data: {
            type: "territories",
            id: BASE_TERRITORY
          }
        }
      }
    },
    included: [
      {
        id: included_price_id,
        type: "appPrices",
        attributes: {
          startDate: nil,
          endDate: nil
        },
        relationships: {
          appPricePoint: {
            data: {
              type: "appPricePoints",
              id: price_point_id
            }
          }
        }
      }
    ]
  }

  expect(:post, "/v1/appPriceSchedules", token, body: body, expected: [201])
end

token = bearer_token
id = app_id(token)

if pricing_configured?(token, id)
  puts "App Store pricing is already configured for app #{id}."
else
  price_point_id = free_price_point_id(token, id)
  create_free_price_schedule(token, id, price_point_id)
  puts "Configured free App Store pricing for app #{id} in #{BASE_TERRITORY}."
end
