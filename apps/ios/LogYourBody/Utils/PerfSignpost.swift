//
// PerfSignpost.swift
// LogYourBody
//
// Lightweight performance signposts for profiling hot paths (launch, scrub,
// chart generation) in Instruments. The OSSignposter calls compile only into
// an opt-in trace build (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` includes
// `LYB_PERF_TRACE`). Checked-in Debug and Release configurations leave the
// flag unset, so the App Store binary does not contain them.
//
// Usage:
//   PerfSignpost.measure("scrub_select_closest") { ... }   // time a sync block
//   let token = PerfSignpost.begin("custom_span"); ...; PerfSignpost.end(token)
//   PerfSignpost.event("launch_first_dashboard_frame", "123 ms")
//

import Foundation
import os

enum PerfSignpost {
    #if LYB_PERF_TRACE
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "LogYourBody",
        category: "perf"
    )
    #endif

    /// Opaque handle for an in-flight interval. Pass it back to `end` to close it.
    struct IntervalToken {
        #if LYB_PERF_TRACE
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        #endif
    }

    /// Begin a named interval that will be closed later by `end`. Prefer `measure`
    /// for spans that begin and end in the same scope.
    static func begin(_ name: StaticString) -> IntervalToken {
        #if LYB_PERF_TRACE
        return IntervalToken(name: name, state: signposter.beginInterval(name))
        #else
        return IntervalToken()
        #endif
    }

    static func end(_ token: IntervalToken) {
        #if LYB_PERF_TRACE
        signposter.endInterval(token.name, token.state)
        #endif
    }

    /// Measure a synchronous block as a signpost interval and return its result.
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        #if LYB_PERF_TRACE
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
        #else
        return try work()
        #endif
    }

    /// Emit a one-shot point-of-interest event. The message autoclosure is only
    /// evaluated in an opt-in `LYB_PERF_TRACE` build.
    static func event(_ name: StaticString, _ message: @autoclosure () -> String = "") {
        #if LYB_PERF_TRACE
        let text = message()
        if text.isEmpty {
            signposter.emitEvent(name)
        } else {
            signposter.emitEvent(name, "\(text, privacy: .public)")
        }
        #endif
    }
}

/// Tracks time-to-first-dashboard-frame as a launch performance baseline.
/// `begin()` is called as early as possible (app `init`); `markFirstDashboardFrame()`
/// is called when the dashboard first appears and logs the elapsed time once.
enum LaunchMetrics {
    #if DEBUG
    private static var processStart: DispatchTime?
    private static var firstFrameLogged = false
    #endif

    /// Record the launch start timestamp. Idempotent.
    static func begin() {
        #if DEBUG
        if processStart == nil {
            processStart = DispatchTime.now()
        }
        #endif
    }

    /// Log the launch → first dashboard frame duration exactly once.
    static func markFirstDashboardFrame() {
        #if DEBUG
        guard !firstFrameLogged else { return }
        firstFrameLogged = true

        let start = processStart ?? DispatchTime.now()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
        let formatted = String(format: "%.1f", elapsedMs)

        AppLogger.ui.info("launch→firstDashboardFrame \(formatted) ms")
        PerfSignpost.event("launch_first_dashboard_frame", "\(formatted) ms")
        #endif
    }
}
