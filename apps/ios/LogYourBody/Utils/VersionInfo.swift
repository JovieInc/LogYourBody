//
// VersionInfo.swift
// LogYourBody
//
import Foundation

/// Simple version info utility that doesn't depend on AppVersionManager
struct VersionInfo {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var formattedVersion: String {
        "Version \(appVersion) (\(buildNumber))"
    }
}
