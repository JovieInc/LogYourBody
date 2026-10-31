# frozen_string_literal: true

require "open3"
require "rubygems/version"

def health_helper(input, *args)
  path = File.expand_path("../app-store-release-health.mjs", __dir__)
  stdout, _stderr, status = Open3.capture3("node", path, *args, stdin_data: JSON.generate(input))
  raise "Release health helper failed" unless status.success?

  JSON.parse(stdout)
end

def health_identity(version)
  return nil unless version

  { "version" => version.dig("attributes", "versionString"), "build" => version.dig("healthBuild", "attributes", "version") }
end

def previous_released_version(versions, candidate)
  number = Gem::Version.new(candidate.dig("attributes", "versionString"))
  released = %w[READY_FOR_SALE READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE]
  versions.select do |version|
    released.include?(version.dig("attributes", "appVersionState")) &&
      Gem::Version.new(version.dig("attributes", "versionString")) < number
  end.max_by { |version| Gem::Version.new(version.dig("attributes", "versionString")) }
end

def guard_release_health(token, version, versions)
  identity = health_identity(version)
  report = begin
    health_helper({ "candidate" => identity, "previous" => health_identity(previous_released_version(versions, version)) })
  rescue StandardError
    { "status" => "UNVERIFIED", "candidate" => identity,
      "summary" => "Release health: **UNVERIFIED** — health evaluation failed.", "reasons" => ["Health helper unavailable"] }
  end
  healthy = report["status"] == "HEALTHY"
  phase = version["healthPhase"]
  action = healthy ? "Health passed; paused releases are never resumed automatically." : "Release request blocked."
  if !healthy && phase&.dig("attributes", "phasedReleaseState") == "ACTIVE"
    body = { data: { type: "appStoreVersionPhasedReleases", id: phase.fetch("id"), attributes: { phasedReleaseState: "PAUSED" } } }
    begin
      paused = expect(:patch, "/v1/appStoreVersionPhasedReleases/#{phase.fetch('id')}", token, body: body)
      raise "Pause not confirmed" unless paused.dig("data", "attributes", "phasedReleaseState") == "PAUSED"

      action = "Phased rollout PAUSED through App Store Connect. Release request blocked."
    rescue StandardError, SystemExit
      action = "PAUSE FAILED; phased rollout may still be ACTIVE. Release request blocked; pause it in App Store Connect."
    end
  elsif phase&.dig("attributes", "phasedReleaseState") == "PAUSED"
    action = "Phased rollout remains PAUSED; manual investigation/resume required."
  end
  report["action"] = action
  remediation = nil
  unless healthy
    begin
      remediation = health_helper(report, "--remediate")
    rescue StandardError
      remediation = { "ok" => false, "reason" => "Remediation NOT filed; issue intake failed" }
    end
    error_with("App Store #{identity&.fetch('version')} release health #{report['status']}. #{action}")
  end
  issue = remediation ? (remediation["ok"] ? "Remediation: #{remediation['action']} #{remediation['identifier']}" : "Remediation NOT filed: #{remediation['reason']}") : "Remediation: none needed."
  append_step_summary(["## App Store #{identity&.fetch('version')} health", "", report.fetch("summary", "UNVERIFIED"), "", "Decision: #{action}", "", issue, ""])
  puts "App Store #{identity&.fetch('version')} health #{report['status']}. #{action} #{issue}"
  healthy
end
