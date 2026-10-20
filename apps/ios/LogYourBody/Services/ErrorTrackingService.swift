import Foundation

#if canImport(Sentry)
import Sentry
#endif

/// Vendor boundary for error tracking. The default implementation forwards to
/// Sentry; tests inject a fake to assert the app-level tag/extra/breadcrumb
/// mapping without touching the vendor SDK.
protocol ErrorTrackingVendor {
    func start()
    func setTag(value: String, key: String)
    func setExtra(value: String, key: String)
    func capture(error: Error)
    func addBreadcrumb(
        level: ErrorTrackingService.BreadcrumbLevel,
        category: String,
        message: String,
        data: [String: String]?
    )
}

final class ErrorTrackingService {
    static let shared = ErrorTrackingService()

    enum BreadcrumbLevel {
        case info
        case error
    }

    private let vendor: ErrorTrackingVendor

    private convenience init() {
        self.init(vendor: SentryErrorTrackingVendor())
    }

    init(vendor: ErrorTrackingVendor) {
        self.vendor = vendor
    }

    func start() {
        vendor.start()
    }

    func capture(appError: AppError, context: ErrorContext) {
        vendor.setTag(value: context.feature, key: "feature")
        if let operation = context.operation {
            vendor.setTag(value: operation, key: "operation")
        }
        if let screen = context.screen {
            vendor.setTag(value: screen, key: "screen")
        }
        if context.userId != nil {
            vendor.setTag(value: ErrorTrackingRedactor.filteredValue, key: "userId")
        }

        let description = String(describing: appError)
        vendor.setExtra(value: ErrorTrackingRedactor.sanitize(description), key: "appError")

        vendor.capture(error: appError)
    }

    func addBreadcrumb(message: String, category: String, level: BreadcrumbLevel = .info, data: [String: String]? = nil) {
        vendor.addBreadcrumb(
            level: level,
            category: category,
            message: ErrorTrackingRedactor.sanitize(message),
            data: data?.reduce(into: [String: String]()) { result, entry in
                result[entry.key] = ErrorTrackingRedactor.sanitize(entry.value, key: entry.key)
            }
        )
    }

    func updateUserId(_ userId: String?) {
        if let userId = userId, !userId.isEmpty {
            vendor.setTag(value: ErrorTrackingRedactor.filteredValue, key: "userId")
        } else {
            vendor.setTag(value: "none", key: "userId")
        }
    }
}

// MARK: - Sentry Adapter

private final class SentryErrorTrackingVendor: ErrorTrackingVendor {
    func start() {
        #if canImport(Sentry)
        let dsn = Configuration.sentryDSN
        guard !dsn.isEmpty else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = Configuration.sentryEnvironment
            options.sendDefaultPii = false
            options.beforeSend = { event in
                ErrorTrackingRedactor.redact(event: event)
            }
            options.beforeBreadcrumb = { breadcrumb in
                ErrorTrackingRedactor.redact(breadcrumb: breadcrumb)
            }

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            if !version.isEmpty, !build.isEmpty {
                options.releaseName = "ios-\(version) (\(build))"
            }

            let sampleRate = Configuration.sentryTracesSampleRate
            if sampleRate > 0 {
                options.tracesSampleRate = NSNumber(value: sampleRate)
            }
        }
        #endif
    }

    func setTag(value: String, key: String) {
        #if canImport(Sentry)
        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
        #endif
    }

    func setExtra(value: String, key: String) {
        #if canImport(Sentry)
        SentrySDK.configureScope { scope in
            scope.setExtra(value: value, key: key)
        }
        #endif
    }

    func capture(error: Error) {
        #if canImport(Sentry)
        SentrySDK.capture(error: error)
        #endif
    }

    func addBreadcrumb(
        level: ErrorTrackingService.BreadcrumbLevel,
        category: String,
        message: String,
        data: [String: String]?
    ) {
        #if canImport(Sentry)
        let breadcrumb = Breadcrumb()

        switch level {
        case .info:
            breadcrumb.level = .info
        case .error:
            breadcrumb.level = .error
        }
        breadcrumb.category = category
        breadcrumb.message = message

        if let data = data {
            var breadcrumbData: [String: Any] = breadcrumb.data ?? [:]
            for (key, value) in data {
                breadcrumbData[key] = value
            }
            breadcrumb.data = breadcrumbData
        }

        SentrySDK.addBreadcrumb(breadcrumb)
        #endif
    }
}

enum ErrorTrackingRedactor {
    static let filteredValue = "[Filtered]"

    private static let sensitiveKeys = [
        "email", "user", "userid", "user_id", "health", "weight", "height",
        "body_fat", "bmi", "glp1", "dose", "medication", "dexa", "metric",
        "photo", "token", "authorization", "phone", "name", "profile"
    ]

    private static let emailPattern = #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
    private static let uuidPattern = #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"#

    static func sanitize(_ value: String, key: String? = nil) -> String {
        if let key, sensitiveKeys.contains(where: { key.lowercased().contains($0) }) {
            return filteredValue
        }
        if value.range(of: emailPattern, options: .regularExpression) != nil ||
            value.range(of: uuidPattern, options: .regularExpression) != nil {
            return filteredValue
        }
        return value
    }

    #if canImport(Sentry)
    static func redact(event: Event) -> Event? {
        event.extra = event.extra?.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = sanitize(String(describing: entry.value), key: entry.key)
        }
        event.tags = event.tags?.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = sanitize(entry.value, key: entry.key)
        }
        event.message = event.message.map { SentryMessage(formatted: sanitize($0.formatted)) }
        event.user = nil
        event.breadcrumbs = event.breadcrumbs?.compactMap { redact(breadcrumb: $0) }
        return event
    }

    static func redact(breadcrumb: Breadcrumb) -> Breadcrumb? {
        breadcrumb.message = breadcrumb.message.map { sanitize($0) }
        breadcrumb.data = breadcrumb.data?.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = sanitize(String(describing: entry.value), key: entry.key)
        }
        return breadcrumb
    }
    #endif
}
