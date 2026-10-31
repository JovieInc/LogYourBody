# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "uri"
require "rubygems/version"

# Release operations only. No customer data or error payloads are logged.
module AppStoreReleaseHealth
  LIVE_STATES = %w[READY_FOR_SALE READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].freeze
  FIELDS = %w[sum(session) count_unique(user) crash_free_rate(session) crash_free_rate(user)].freeze

  def self.json_request(method, url, token, body: nil)
    raise "missing API token" if token.to_s.empty?

    uri = URI(url)
    req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(req) }
    raise "#{uri.host} returned HTTP #{response.code}" unless (200..299).cover?(response.code.to_i)

    JSON.parse(response.body)
  end

  class Monitor
    def initialize(versions:, asc:)
      @versions = versions
      @asc = asc
    end

    def phased_release(version)
      @asc.call(:get, "/v1/appStoreVersions/#{version.fetch('id')}/appStoreVersionPhasedRelease", nil)["data"]
    end

    def release_name(version)
      build = @asc.call(:get, "/v1/appStoreVersions/#{version.fetch('id')}/build", nil).dig("data", "attributes", "version")
      raise "attached App Store build is missing" if build.to_s.empty?

      "ios-#{version.fetch('attributes').fetch('versionString')} (#{build})"
    end

    def previous_version(version)
      target = Gem::Version.new(version.fetch("attributes").fetch("versionString"))
      @versions.select do |item|
        LIVE_STATES.include?(item.dig("attributes", "appVersionState")) &&
          Gem::Version.new(item.fetch("attributes").fetch("versionString")) < target
      end.max_by { |item| Gem::Version.new(item.fetch("attributes").fetch("versionString")) }
    end

    def snapshot(version)
      raise "previous released version is missing" unless version

      release = release_name(version)
      query = FIELDS.map { |field| ["field", field] } + [
        ["project", ENV.fetch("SENTRY_PROJECT", "log-your-body-ios")],
        ["environment", "production"], ["statsPeriod", "24h"],
        ["groupBy", "release"], ["includeSeries", "0"], ["interval", "1h"],
        ["query", "release:#{JSON.generate(release)}"]
      ]
      org = URI.encode_www_form_component(ENV.fetch("SENTRY_ORG", "jovie"))
      payload = AppStoreReleaseHealth.json_request(:get, "https://sentry.io/api/0/organizations/#{org}/sessions/?#{URI.encode_www_form(query)}", ENV["SENTRY_AUTH_TOKEN"])
      groups = payload.fetch("groups")
      raise "missing or ambiguous exact-build session data for #{release}" unless groups.length == 1 && groups.first.dig("by", "release") == release
      # Sentry rounds the end up to the next interval boundary (at most one hour).
      raise "stale or invalid Sentry session window" unless (-3600..7200).cover?(Time.now - Time.iso8601(payload.fetch("end")))

      totals = groups.first.fetch("totals")
      FIELDS.each { |field| raise "invalid #{field}" unless totals[field].is_a?(Numeric) && totals[field].finite? }
      %w[crash_free_rate(session) crash_free_rate(user)].each do |field|
        raise "invalid #{field} (expected fraction)" unless (0..1).cover?(totals[field])
      end
      raise "invalid session/user counts" unless totals["sum(session)"] >= 0 && totals["count_unique(user)"] >= 0 && totals["count_unique(user)"] <= totals["sum(session)"]

      { release: release, totals: totals }
    rescue StandardError => error
      { release: release, error: error.message }
    end

    def setting(name, default, range)
      value = Float(ENV.fetch(name, default))
      raise "invalid #{name}" unless value.finite? && range.cover?(value)

      value
    end

    def evaluate(current, previous)
      minimum = setting("RELEASE_HEALTH_MIN_CRASH_FREE_PERCENT", "99.5", 0..100)
      regression = setting("RELEASE_HEALTH_MAX_REGRESSION_PP", "0.5", 0..100)
      sessions = setting("RELEASE_HEALTH_MIN_SESSIONS", "100", 1..Float::INFINITY)
      users = setting("RELEASE_HEALTH_MIN_USERS", "20", 1..Float::INFINITY)
      policy = "24h production; floor #{minimum}%; maximum regression #{regression} percentage points; minimum #{sessions.to_i} sessions / #{users.to_i} users per build"
      missing = [current, previous].filter_map { |item| item[:error] }
      reasons = []
      # A known absolute breach still stops rollout when the comparison is unavailable.
      unless current[:error]
        %w[session user].each do |metric|
          field = "crash_free_rate(#{metric})"
          rate = current.fetch(:totals).fetch(field) * 100
          reasons << "crash-free #{metric}s #{rate.round(3)}% below #{minimum}%" if rate < minimum
          unless previous[:error]
            drop = previous.fetch(:totals).fetch(field) * 100 - rate
            reasons << "crash-free #{metric}s regressed #{drop.round(3)} percentage points" if drop > regression + 1e-9
          end
        end
      end
      [current, previous].each do |item|
        next if item[:error]

        totals = item.fetch(:totals)
        if totals.fetch("sum(session)") < sessions || totals.fetch("count_unique(user)") < users
          missing << "insufficient sample for #{item[:release]}"
        end
      end
      status = if reasons.any?
                 "BREACHED"
               elsif missing.any?
                 "UNVERIFIED"
               else
                 "HEALTHY"
               end
      { status: status, reasons: reasons + missing, policy: policy }
    rescue StandardError => error
      { status: "UNVERIFIED", reasons: [error.message], policy: "invalid health policy" }
    end

    def summary(lines)
      puts lines.join("\n")
      path = ENV["GITHUB_STEP_SUMMARY"].to_s
      File.open(path, "a") { |file| file.puts(lines) } unless path.empty?
    end

    def remediation(version, lines)
      repository = ENV.fetch("GITHUB_REPOSITORY")
      token = ENV["GH_TOKEN"]
      title = "[LYB-139] App Store #{version.fetch('attributes').fetch('versionString')} release health"
      base = "https://api.github.com/repos/#{repository}/issues"
      issue = nil
      page = 1
      loop do
        issues = AppStoreReleaseHealth.json_request(:get, "#{base}?state=all&per_page=100&page=#{page}", token)
        issue = issues.find { |item| !item["pull_request"] && item["title"] == title }
        break if issue || issues.length < 100

        page += 1
      end
      run_url = "https://github.com/#{repository}/actions/runs/#{ENV.fetch('GITHUB_RUN_ID')}"
      body = (lines + ["", "Run: #{run_url}", "", "Investigate this exact build in Sentry, ship a corrected build, and explicitly resume in App Store Connect only after verified health. This monitor never resumes a paused release."]).join("\n")
      # Refresh one issue in place; reopen it if a subsequent run detects the problem again.
      result = if issue
                 AppStoreReleaseHealth.json_request(:patch, "#{base}/#{issue.fetch('number')}", token, body: { state: "open", body: body })
               else
                 AppStoreReleaseHealth.json_request(:post, base, token, body: { title: title, body: body })
               end
      summary(["Remediation: #{result.fetch('html_url')}"])
    end

    def check(version, phase:)
      current = snapshot(version)
      previous = snapshot(previous_version(version))
      decision = evaluate(current, previous)
      unless phase
        decision[:status] = "UNVERIFIED" if decision[:status] == "HEALTHY"
        decision[:reasons] << "phased release configuration is missing"
      end
      lines = ["## App Store release health: #{decision[:status]}", "", decision[:policy], "",
               "Current: `#{current[:release] || 'unknown'}` — #{current[:totals] || current[:error]}",
               "Previous: `#{previous[:release] || 'unknown'}` — #{previous[:totals] || previous[:error]}",
               "Decision: #{decision[:status] == 'HEALTHY' ? 'release permitted; an existing pause remains paused' : 'release blocked'}."]
      lines.concat(decision[:reasons].map { |reason| "- #{reason}" })
      summary(lines)
      return true if decision[:status] == "HEALTHY"

      warn "::error::App Store release health #{decision[:status]}"
      failures = []
      if phase && phase.dig("attributes", "phasedReleaseState") == "ACTIVE"
        begin
          id = phase.fetch("id")
          result = @asc.call(:patch, "/v1/appStoreVersionPhasedReleases/#{id}", { data: { type: "appStoreVersionPhasedReleases", id: id, attributes: { phasedReleaseState: "PAUSED" } } })
          raise "App Store Connect did not confirm PAUSED" unless result.dig("data", "attributes", "phasedReleaseState") == "PAUSED"

          summary(["Action: phased release PAUSED (#{id})."])
        rescue StandardError => error
          failures << "Pause FAILED: #{error.message}"
        end
      else
        summary(["Action: no release requested; phased state #{phase&.dig('attributes', 'phasedReleaseState') || 'unavailable'}. No automatic resume."])
      end
      # Filing still happens when Apple's pause API fails; pausing does not depend on GitHub.
      begin
        remediation(version, lines + failures)
      rescue StandardError => error
        failures << "Remediation issue FAILED: #{error.message}"
      end
      summary(failures) if failures.any?
      false
    end
  end
end
