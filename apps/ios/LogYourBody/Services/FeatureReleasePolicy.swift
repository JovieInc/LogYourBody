//
// FeatureReleasePolicy.swift
// LogYourBody
//
// Native adapter for the shared Jovie/LYB feature release lifecycle
// (JOV-8056). Evaluation is deterministic and dependency-free so the same
// versioned policy fixtures (shared/release/) run identically on both
// platforms.
//

import Foundation

/// Lifecycle stage a feature descriptor is in.
enum FeatureReleaseStage: String, Codable {
    /// Compiled in but not exposed to anyone by policy.
    case disabled
    /// Automatic exposure for verified dogfood principals; ordinary
    /// customers still need the positive enable gate.
    case dogfood
    /// Public baseline: the approved surface is the code default even when
    /// remote config is missing, stale, or offline.
    case graduated
}

/// Who is asking. The shared dogfood roster (JOV-6644) resolves the signed
/// in principal to one of these values; the evaluator never infers identity
/// itself and never sends it to the analytics vendor.
enum FeatureReleaseActor: String, Codable {
    /// Ordinary customer / comparison mode. The default.
    case ordinaryCustomer
    /// Verified founder/staff human on the shared roster.
    case dogfoodHuman
    /// Registered autonomous agent test principal.
    case dogfoodAgent

    var isDogfoodPrincipal: Bool { self != .ordinaryCustomer }
}

/// Freshness of the remote config that produced the observed gate values.
enum FeatureReleaseConfigState: String, Codable {
    /// Values observed from a currently reachable config.
    case fresh
    /// Values read from a cache older than its TTL.
    case stale
    /// No config at all: first launch offline, fetch failed, etc.
    case missing
}

/// Static descriptor of one controllable feature, versioned with the code
/// that implements the feature.
struct FeatureReleaseDescriptor: Equatable, Codable {
    /// Positive enable gate key. `true` can only ever turn a feature on;
    /// `false` is never a blanket off switch.
    var flagKey: String
    /// Inverse-meaning emergency stop key (e.g. `home_v2_kill_switch`).
    /// Honored only while the reporting config is fresh — absence of config
    /// is not itself a stop.
    var killSwitchKey: String?
    var stage: FeatureReleaseStage
    /// Oldest installed build containing the feature's code. Exposure on an
    /// older binary is BLOCKED_BUILD: code that is not installed cannot be
    /// enabled remotely.
    var minimumBuild: Int?
}

/// Everything about the actor, install, and observed config that a single
/// evaluation depends on.
struct FeatureReleaseContext: Equatable, Codable {
    var actor: FeatureReleaseActor = .ordinaryCustomer
    /// The installed bundle's CFBundleVersion as an integer.
    var installedBuild: Int = 0
    var configState: FeatureReleaseConfigState = .fresh
    /// Last observed value of `flagKey`. Trusted only when the config is
    /// fresh or stale; a missing config cannot vouch for a `true`.
    var enableGate: Bool = false
    /// Last observed value of `killSwitchKey`. Honored only when fresh.
    var killSwitch: Bool = false
}

enum FeatureReleaseReason: String, Codable {
    case enableGate
    case dogfoodPrincipal
    case graduatedDefault
    case disabledStage
    case ordinaryCustomer
    /// Installed binary predates `minimumBuild` — BLOCKED_BUILD.
    case blockedBuild
    /// Fresh config asserted the emergency stop — BLOCKED_EXPOSURE.
    case killSwitch
}

struct FeatureReleaseDecision: Equatable, Codable {
    var isEnabled: Bool
    var reason: FeatureReleaseReason
}

enum FeatureReleaseEvaluator {
    static func evaluate(
        _ descriptor: FeatureReleaseDescriptor,
        context: FeatureReleaseContext
    ) -> FeatureReleaseDecision {
        if context.configState == .fresh, context.killSwitch {
            return FeatureReleaseDecision(isEnabled: false, reason: .killSwitch)
        }
        if let minimumBuild = descriptor.minimumBuild, context.installedBuild < minimumBuild {
            return FeatureReleaseDecision(isEnabled: false, reason: .blockedBuild)
        }
        switch descriptor.stage {
        case .disabled:
            return FeatureReleaseDecision(isEnabled: false, reason: .disabledStage)
        case .graduated:
            // Public baseline: survives missing/offline/stale config and a
            // `false` enable gate — the gate is positive-only and never a
            // blanket off. Only a fresh kill switch stops it (handled above).
            return FeatureReleaseDecision(isEnabled: true, reason: .graduatedDefault)
        case .dogfood:
            if context.actor.isDogfoodPrincipal {
                return FeatureReleaseDecision(isEnabled: true, reason: .dogfoodPrincipal)
            }
            if context.configState != .missing, context.enableGate {
                return FeatureReleaseDecision(isEnabled: true, reason: .enableGate)
            }
            return FeatureReleaseDecision(isEnabled: false, reason: .ordinaryCustomer)
        }
    }
}
