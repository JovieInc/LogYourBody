# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "release-approved-app-store-version"

class ReleaseHealthHarness
  public :release_approved_app_store_version
  attr_accessor :verdict, :phase_state, :selected_state, :pause_failure, :issue_failure, :release_type
  attr_reader :calls, :checks, :summaries

  def initialize
    @verdict = "HEALTHY"
    @selected_state = "PENDING_DEVELOPER_RELEASE"
    @release_type = "MANUAL"
    @calls, @checks, @summaries = [], [], []
  end

  def bearer_token; "token"; end
  def app_id(_token); "app"; end
  def active_review_submission_for_version(*); nil; end
  def append_step_summary(lines); @summaries.concat(lines); end

  def app_store_versions(*)
    [
      { "id" => "new", "attributes" => { "versionString" => "1.3.0", "appVersionState" => selected_state, "releaseType" => release_type },
        "healthBuild" => { "attributes" => { "version" => "203" } },
        "healthPhase" => phase_state ? { "id" => "phase", "attributes" => { "phasedReleaseState" => phase_state } } : nil },
      { "id" => "old", "attributes" => { "versionString" => "1.2.0", "appVersionState" => "REPLACED_WITH_NEW_VERSION" },
        "healthBuild" => { "attributes" => { "version" => "202" } } }
    ]
  end

  def health_helper(input, *args)
    if args.include?("--remediate")
      @calls << [:issue, input]
      return { "ok" => !issue_failure, "action" => "updated", "identifier" => "LYB-fixture", "reason" => "intake failed" }
    end
    @checks << input
    raise "node unavailable" if verdict == "HELPER_FAILURE"

    { "status" => verdict, "candidate" => input["candidate"], "summary" => "Health: #{verdict}", "reasons" => [] }
  end

  def expect(method, path, _token, body: nil, expected: [200])
    @calls << [method, path, body, expected]
    raise "ASC rejected pause" if pause_failure

    { "data" => { "attributes" => { "phasedReleaseState" => "PAUSED", "releaseType" => "MANUAL" } } }
  end
end

class ReleaseApprovedAppStoreVersionTest < Minitest::Test
  def setup
    @original_version = ENV["APP_VERSION"]
    ENV["APP_VERSION"] = "1.3.0"
    @monitor = ReleaseHealthHarness.new
  end

  def teardown
    @original_version ? ENV["APP_VERSION"] = @original_version : ENV.delete("APP_VERSION")
  end

  def run_monitor(fails: false)
    capture_io do
      if fails
        assert_equal 1, assert_raises(SystemExit) { @monitor.release_approved_app_store_version }.status
      else
        @monitor.release_approved_app_store_version
      end
    end
  end

  def test_healthy_release_queries_exact_candidate_and_previous_before_requesting_release
    run_monitor
    assert_equal [{ "candidate" => { "version" => "1.3.0", "build" => "203" },
                    "previous" => { "version" => "1.2.0", "build" => "202" } }], @monitor.checks
    assert_equal [:post], @monitor.calls.map(&:first)
    assert_equal "/v1/appStoreVersionReleaseRequests", @monitor.calls.first[1]
    assert_equal "new", @monitor.calls.first[2].dig(:data, :relationships, :appStoreVersion, :data, :id)
    assert_includes @monitor.summaries.join, "after HEALTHY decision"
  end

  def test_breached_release_is_blocked_and_files_remediation
    @monitor.verdict = "BREACHED"
    run_monitor(fails: true)
    assert_equal [:issue], @monitor.calls.map(&:first)
    assert_includes @monitor.summaries.join, "Release request blocked"
  end

  def test_breached_active_rollout_pauses_before_filing
    @monitor.verdict = "BREACHED"
    @monitor.phase_state = "ACTIVE"
    @monitor.selected_state = "READY_FOR_DISTRIBUTION"
    run_monitor(fails: true)
    assert_equal [:patch, :issue], @monitor.calls.map(&:first)
    assert_equal "/v1/appStoreVersionPhasedReleases/phase", @monitor.calls.first[1]
    assert_equal "PAUSED", @monitor.calls.first[2].dig(:data, :attributes, :phasedReleaseState)
    assert_includes @monitor.summaries.join, "Phased rollout PAUSED"
    assert_includes @monitor.summaries.join, "LYB-fixture"
  end

  def test_unverified_data_blocks_release_and_pauses_active_rollout
    [nil, "ACTIVE"].each do |phase|
      @monitor = ReleaseHealthHarness.new
      @monitor.verdict, @monitor.phase_state = "UNVERIFIED", phase
      run_monitor(fails: true)
      refute_includes @monitor.calls.map(&:first), :post
      assert_equal phase ? [:patch, :issue] : [:issue], @monitor.calls.map(&:first)
      assert_includes @monitor.summaries.join, "UNVERIFIED"
    end
  end

  def test_healthy_paused_rollout_is_never_resumed
    @monitor.phase_state, @monitor.selected_state = "PAUSED", "READY_FOR_SALE"
    run_monitor
    assert_empty @monitor.calls
    assert_includes @monitor.summaries.join, "remains PAUSED"
  end

  def test_new_marketing_version_does_not_hide_an_older_active_rollout
    @monitor.phase_state, @monitor.selected_state = "ACTIVE", "READY_FOR_SALE"
    ENV["APP_VERSION"] = "1.4.0"
    capture_io { assert_raises(SystemExit) { @monitor.release_approved_app_store_version } }
    assert_equal 1, @monitor.checks.length
  end

  def test_pause_and_filing_failures_are_visible_and_do_not_request_release
    @monitor.verdict, @monitor.phase_state = "BREACHED", "ACTIVE"
    @monitor.pause_failure, @monitor.issue_failure = true, true
    run_monitor(fails: true)
    assert_equal [:patch, :issue], @monitor.calls.map(&:first)
    assert_includes @monitor.summaries.join, "PAUSE FAILED"
    assert_includes @monitor.summaries.join, "Remediation NOT filed"
  end

  def test_helper_failure_is_unverified_and_pauses
    @monitor.verdict, @monitor.phase_state = "HELPER_FAILURE", "ACTIVE"
    run_monitor(fails: true)
    assert_equal [:patch, :issue], @monitor.calls.map(&:first)
    assert_includes @monitor.summaries.join, "UNVERIFIED"
  end

  def test_review_state_does_not_request_release
    @monitor.selected_state = "WAITING_FOR_REVIEW"
    run_monitor
    assert_empty @monitor.checks
    assert_empty @monitor.calls
  end

  def test_existing_automatic_submission_is_switched_to_manual_while_in_review
    @monitor.selected_state, @monitor.release_type = "WAITING_FOR_REVIEW", "AFTER_APPROVAL"
    run_monitor
    assert_equal [:patch], @monitor.calls.map(&:first)
    assert_equal "/v1/appStoreVersions/new", @monitor.calls.first[1]
    assert_equal "MANUAL", @monitor.calls.first[2].dig(:data, :attributes, :releaseType)
    assert_includes @monitor.summaries.join, "releaseType changed to MANUAL"
  end

  def test_manual_release_mode_failure_is_visible
    @monitor.selected_state, @monitor.release_type = "WAITING_FOR_REVIEW", "AFTER_APPROVAL"
    @monitor.pause_failure = true
    run_monitor(fails: true)
    assert_includes @monitor.summaries.join, "UNVERIFIED"
    assert_equal [:patch], @monitor.calls.map(&:first)
  end

  def test_version_inventory_follows_pages_and_resolves_build_and_phase_by_resource_type
    reader = Object.new
    paths = []
    pages = [
      { "data" => [{ "id" => "new", "relationships" => {
        "build" => { "data" => { "type" => "builds", "id" => "build" } },
        "appStoreVersionPhasedRelease" => { "data" => { "type" => "appStoreVersionPhasedReleases", "id" => "phase" } }
      } }], "included" => [
        { "type" => "builds", "id" => "build", "attributes" => { "version" => "203" } },
        { "type" => "appStoreVersionPhasedReleases", "id" => "phase", "attributes" => { "phasedReleaseState" => "ACTIVE" } }
      ], "links" => { "next" => "https://api.appstoreconnect.apple.com/v1/apps/app/appStoreVersions?cursor=2" } },
      { "data" => [{ "id" => "old" }], "links" => { "next" => nil } }
    ]
    reader.define_singleton_method(:expect) do |_method, path, _token|
      paths << path
      pages.shift
    end
    versions = reader.send(:app_store_versions, "token", "app")
    assert_equal ["new", "old"], versions.map { |item| item["id"] }
    assert_equal "203", versions.first.dig("healthBuild", "attributes", "version")
    assert_equal "ACTIVE", versions.first.dig("healthPhase", "attributes", "phasedReleaseState")
    assert_equal "/v1/apps/app/appStoreVersions?cursor=2", paths.last
  end

  def test_real_node_bridge_returns_visible_unverified_without_credentials
    previous_token = ENV.delete("SENTRY_AUTH_TOKEN")
    report = Object.new.send(:health_helper, { "candidate" => { "version" => "1.3.0", "build" => "203" } })
    assert_equal "UNVERIFIED", report["status"]
    assert_includes report["summary"], "SENTRY_AUTH_TOKEN missing"
  ensure
    ENV["SENTRY_AUTH_TOKEN"] = previous_token if previous_token
  end
end
