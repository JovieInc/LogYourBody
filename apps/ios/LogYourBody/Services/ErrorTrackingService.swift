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
        if let userId = context.userId {
            vendor.setTag(value: userId, key: "userId")
        }

        let description = String(describing: appError)
        vendor.setExtra(value: description, key: "appError")

        vendor.capture(error: appError)
    }

    func addBreadcrumb(message: String, category: String, level: BreadcrumbLevel = .info, data: [String: String]? = nil) {
        vendor.addBreadcrumb(level: level, category: category, message: message, data: data)
    }

    func updateUserId(_ userId: String?) {
        if let userId = userId, !userId.isEmpty {
            vendor.setTag(value: userId, key: "userId")
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
