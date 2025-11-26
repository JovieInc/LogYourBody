//
// AnalyticsService.swift
// LogYourBody
//
// App-wide analytics facade using a vendor-specific adapter (Statsig).
//

import Foundation

#if canImport(Statsig)
import Statsig

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
/// implementation (currently Statsig) so that vendor details remain
/// isolated from product code.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let client: AnalyticsClient

    private init(client: AnalyticsClient = StatsigAnalyticsClient()) {
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

// MARK: - Statsig Adapter

private final class StatsigAnalyticsClient: AnalyticsClient {
    func start() {
        let sdkKey = Configuration.statsigClientSDKKey
        guard !sdkKey.isEmpty else {
            return
        }

        let tierString = Configuration.statsigEnvironmentTier.lowercased()
        let environment: StatsigEnvironment?

        switch tierString {
        case "production":
            environment = StatsigEnvironment(tier: .Production)
        case "staging":
            environment = StatsigEnvironment(tier: .Staging)
        case "development":
            environment = StatsigEnvironment(tier: .Development)
        default:
            environment = nil
        }

        let options: StatsigOptions
        if let environment {
            options = StatsigOptions(environment: environment)
        } else {
            options = StatsigOptions()
        }

        Statsig.initialize(sdkKey: sdkKey, user: nil, options: options)
    }

    func identify(userId: String?, properties: [String: String]?) {
        let trimmedId = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (trimmedId?.isEmpty ?? true) ? nil : trimmedId

        var email: String?
        if let value = properties?["email"], !value.isEmpty {
            email = value
        }

        var country: String?
        if let value = properties?["country"], !value.isEmpty {
            country = value
        }

        var locale: String?
        if let value = properties?["locale"], !value.isEmpty {
            locale = value
        }

        var custom: [String: StatsigUserCustomTypeConvertible]?
        if let properties, !properties.isEmpty {
            var dict: [String: StatsigUserCustomTypeConvertible] = [:]
            for (key, value) in properties {
                dict[key] = value
            }
            custom = dict
        }

        let user = StatsigUser(
            userID: id,
            email: email,
            ip: nil,
            country: country,
            locale: locale,
            appVersion: AppVersion.current,
            custom: custom,
            privateAttributes: nil,
            optOutNonSdkMetadata: false,
            customIDs: nil,
            userAgent: nil
        )

        Statsig.updateUserWithResult(user)
    }

    func track(event: String, properties: [String: String]?) {
        if let properties {
            Statsig.logEvent(event, metadata: properties)
        } else {
            Statsig.logEvent(event)
        }
    }

    func reset() {
        let user = StatsigUser(
            userID: nil,
            email: nil,
            ip: nil,
            country: nil,
            locale: nil,
            appVersion: AppVersion.current,
            custom: nil,
            privateAttributes: nil,
            optOutNonSdkMetadata: false,
            customIDs: nil,
            userAgent: nil
        )

        Statsig.updateUserWithResult(user)
    }

    func isFeatureEnabled(flagKey: String) -> Bool {
        Statsig.checkGate(flagKey)
    }
}
#endif
