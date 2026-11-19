require 'json'
require 'tmpdir'
require 'fileutils'
require 'minitest/autorun'

module SharedValues
  XCODEBUILD_ARCHIVE = :XCODEBUILD_ARCHIVE
end

class BetaLaneHarness
  attr_reader :events, :lane_context

  def initialize(source, filename)
    @events = []
    @lane_context = {}
    project = 'LogYourBody.xcodeproj'
    testflight_upload_options = ->(**options) { options }
    eval(source, binding, filename)
  end

  def desc(*) end
  def lane(name, &block) define_singleton_method(name, &block) end
  def setup_app_store_connect_api; @events << :authenticate end
  def clean_build_artifacts; @events << [:cleanup, lane_context.dup] end
  def increment_build_number(**options); @events << [:increment, options] end
  def build(**options)
    @events << [:build, options]
    lane_context[:XCODEBUILD_ARCHIVE] = '/fixture/archive.xcarchive'
    lane_context[:IPA_OUTPUT_PATH] = '/fixture/build/LogYourBody.ipa'
    lane_context[:DSYM_OUTPUT_PATH] = '/fixture/build/LogYourBody.app.dSYM.zip'
    lane_context[:GENERATED_PLIST_PATH] = '/fixture/export-options.plist'
    lane_context[:APP_STORE_CONNECT_API_KEY] = 'fixture-secret-must-not-persist'
    { output_path: './build/LogYourBody.ipa' }
  end
  def upload_to_testflight(**options); @events << [:upload, options] end
  def sentry_upload_symbols(**options); @events << [:symbols, options] end
  def notify_success(**options); @events << [:notify, options] end
end

class BetaSplitTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('lyb-376-beta-')
    @filename = File.join(@dir, 'fastlane/Fastfile.release')
    FileUtils.mkdir_p(File.dirname(@filename))
    FileUtils.mkdir_p(File.join(@dir, 'build'))
    @source = File.read(File.expand_path('../Fastfile.release', __dir__))
    @receipt = File.join(@dir, 'build/beta-archive.json')
  end

  def teardown; FileUtils.remove_entry(@dir) end
  def harness; BetaLaneHarness.new(@source, @filename) end

  def test_archive_has_no_upload_and_preserves_build_options
    runner = harness
    runner.beta_archive
    refute runner.events.any? { |event| event.is_a?(Array) && event.first == :upload }
    options = runner.events.find { |event| event.is_a?(Array) && event.first == :build }.last
    assert_equal 'Release', options[:configuration]
    assert_equal 'app-store', options[:export_method]
    assert_equal './build', options[:output_directory]
    assert_equal true, options[:clean_artifacts]
    refute_includes File.read(@receipt), 'fixture-secret-must-not-persist'
  end

  def test_upload_in_fresh_process_restores_artifacts_and_original_options
    harness.beta_archive
    runner = harness
    runner.beta_upload
    upload = runner.events.find { |event| event.is_a?(Array) && event.first == :upload }.last
    assert_equal({ ipa: './build/LogYourBody.ipa', groups: ['Beta Testers'], distribute_external: true }, upload)
    assert_includes runner.events, [:symbols, { dsym_dir: '/fixture/archive.xcarchive/dSYMs' }]
    cleanup = runner.events.find { |event| event.is_a?(Array) && event.first == :cleanup }.last
    assert_equal '/fixture/archive.xcarchive', cleanup[:XCODEBUILD_ARCHIVE]
    assert_equal '/fixture/build/LogYourBody.app.dSYM.zip', cleanup[:DSYM_OUTPUT_PATH]
    assert_equal '/fixture/export-options.plist', cleanup[:GENERATED_PLIST_PATH]
    assert_equal :authenticate, runner.events.first
    assert_includes runner.events, [:notify, { context: 'beta' }]
    refute File.exist?(@receipt)
  end

  def test_local_wrapper_still_archives_then_uploads
    runner = harness
    runner.beta
    actions = runner.events.select { |event| event.is_a?(Array) }.map(&:first)
    assert_operator actions.index(:build), :<, actions.index(:upload)
    refute File.exist?(@receipt)
  end

  def test_upload_without_archive_receipt_fails_before_upload
    runner = harness
    assert_raises(Errno::ENOENT) { runner.beta_upload }
    refute runner.events.any? { |event| event.is_a?(Array) && event.first == :upload }
  end
end
