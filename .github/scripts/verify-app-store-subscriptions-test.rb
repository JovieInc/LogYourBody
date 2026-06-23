# frozen_string_literal: true

require "minitest/autorun"

load File.expand_path("verify-app-store-subscriptions.rb", __dir__)

class VerifyAppStoreSubscriptionsTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @original_net_http_start = Net::HTTP.method(:start)
    @original_env = {
      "APP_STORE_CONNECT_MAX_REQUEST_ATTEMPTS" => ENV["APP_STORE_CONNECT_MAX_REQUEST_ATTEMPTS"],
      "APP_STORE_CONNECT_RETRY_BASE_SECONDS" => ENV["APP_STORE_CONNECT_RETRY_BASE_SECONDS"]
    }
    ENV["APP_STORE_CONNECT_RETRY_BASE_SECONDS"] = "0"
  end

  def teardown
    original_start = @original_net_http_start
    Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
      original_start.call(*args, **kwargs, &block)
    end

    @original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def stub_http_responses(*responses)
    requests = []

    Net::HTTP.define_singleton_method(:start) do |_hostname, _port, use_ssl:, &block|
      raise "expected SSL App Store Connect request" unless use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << request
        response = responses.shift
        raise "missing stubbed response" unless response

        response
      end

      block.call(http)
    end

    requests
  end

  def test_request_retries_transient_server_error
    ENV["APP_STORE_CONNECT_MAX_REQUEST_ATTEMPTS"] = "3"
    requests = stub_http_responses(
      FakeResponse.new("500", '{"errors":[{"status":"500"}]}'),
      FakeResponse.new("200", '{"data":[]}')
    )

    _stdout, stderr = capture_io do
      status, parsed = request(:get, "/v1/apps/app-id/subscriptionGroups", "token")
      assert_equal 200, status
      assert_equal({ "data" => [] }, parsed)
    end

    assert_equal 2, requests.length
    assert_includes stderr, "returned 500; retrying in 0.0s (attempt 2/3)."
  end

  def test_expect_fails_after_bounded_retries
    ENV["APP_STORE_CONNECT_MAX_REQUEST_ATTEMPTS"] = "2"
    requests = stub_http_responses(
      FakeResponse.new("500", '{"errors":[{"status":"500"}]}'),
      FakeResponse.new("500", '{"errors":[{"status":"500"}]}')
    )
    exit_status = nil

    _stdout, stderr = capture_io do
      error = assert_raises(SystemExit) do
        expect(:get, "/v1/apps/app-id/subscriptionGroups", "token")
      end
      exit_status = error.status
    end

    assert_equal 1, exit_status
    assert_equal 2, requests.length
    assert_includes stderr, "returned 500; retrying in 0.0s (attempt 2/2)."
    assert_includes stderr, "App Store Connect GET /v1/apps/app-id/subscriptionGroups returned 500"
  end

  def test_request_retries_transient_network_error
    ENV["APP_STORE_CONNECT_MAX_REQUEST_ATTEMPTS"] = "2"
    requests = []

    Net::HTTP.define_singleton_method(:start) do |_hostname, _port, use_ssl:, &block|
      raise "expected SSL App Store Connect request" unless use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << request
        raise Net::ReadTimeout if requests.length == 1

        FakeResponse.new("200", '{"data":[]}')
      end

      block.call(http)
    end

    _stdout, stderr = capture_io do
      status, parsed = request(:get, "/v1/apps/app-id/subscriptionGroups", "token")
      assert_equal 200, status
      assert_equal({ "data" => [] }, parsed)
    end

    assert_equal 2, requests.length
    assert_includes stderr, "failed with Net::ReadTimeout; retrying in 0.0s (attempt 2/2)."
  end
end
