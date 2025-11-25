//
// AnalyticsService.swift
// LogYourBody
//
// App-wide analytics facade using a vendor-specific adapter (PostHog).
//

import Foundation

#if canImport(PostHog)
import PostHog

protocol AnalyticsClient {
    func start()
    func identify(userId: String?, properties: [String: String]?)
    func track(event: String, properties: [String: String]?)
    func reset()
    func isFeatureEnabled(flagKey: String) -> Bool
}

/// Central analytics service used throughout the app.
///
/// This exposes a vendor-agnostic API and delegates to a concrete client
/// implementation (currently PostHog) so that vendor details remain
/// isolated from product code.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let client: AnalyticsClient

    private init(client: AnalyticsClient = PostHogAnalyticsClient()) {
        self.client = client
    }

    func start() {
        client.start()
    }

    func identify(userId: String?, properties: [String: String]? = nil) {
        client.identify(userId: userId, properties: properties)
    }

    func track(event: String, properties: [String: String]? = nil) {
        client.track(event: event, properties: properties)
    }

    func reset() {
        client.reset()
    }

    func isFeatureEnabled(flagKey: String) -> Bool {
        client.isFeatureEnabled(flagKey: flagKey)
    }
}

// MARK: - PostHog Adapter

private final class PostHogAnalyticsClient: AnalyticsClient {
    func start() {
        let apiKey = Configuration.posthogAPIKey
        guard !apiKey.isEmpty else { return }

        let host = Configuration.posthogHost
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)
    }

    func identify(userId: String?, properties: [String: String]?) {
        guard let userId = userId, !userId.isEmpty else { return }
        PostHogSDK.shared.identify(userId, properties: properties ?? [:])
    }

    func track(event: String, properties: [String: String]?) {
        PostHogSDK.shared.capture(event, properties: properties ?? [:])
    }

    func reset() {
        PostHogSDK.shared.reset()
    }

    func isFeatureEnabled(flagKey: String) -> Bool {
        PostHogSDK.shared.isFeatureEnabled(flagKey)
    }
}

#endif
