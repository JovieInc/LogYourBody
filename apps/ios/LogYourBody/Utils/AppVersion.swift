//
// AppVersion.swift
// LogYourBody
//
import Foundation

struct AppVersion {
    static let current: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    /// Full version string with build number
    static var fullVersion: String {
        "Version \(current) (\(build))"
    }

    /// Short version string without "Version" prefix
    static var shortVersion: String {
        current
    }
}
