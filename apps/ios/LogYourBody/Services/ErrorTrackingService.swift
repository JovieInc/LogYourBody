import Foundation

#if canImport(Sentry)
import Sentry
#endif

final class ErrorTrackingService {
    static let shared = ErrorTrackingService()

    enum BreadcrumbLevel {
        case info
        case error
    }

    private init() {}

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

    func capture(appError: AppError, context: ErrorContext) {
        #if canImport(Sentry)
        SentrySDK.configureScope { scope in
            scope.setTag(value: context.feature, key: "feature")
            if let operation = context.operation {
                scope.setTag(value: operation, key: "operation")
            }
            if let screen = context.screen {
                scope.setTag(value: screen, key: "screen")
            }
            if let userId = context.userId {
                scope.setTag(value: userId, key: "userId")
            }

            let description = String(describing: appError)
            scope.setExtra(value: description, key: "appError")
        }

        SentrySDK.capture(error: appError)
        #endif
    }

    func addBreadcrumb(message: String, category: String, level: BreadcrumbLevel = .info, data: [String: String]? = nil) {
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
            for (key, value) in data {
                breadcrumb.setData(value: value, key: key)
            }
        }

        SentrySDK.addBreadcrumb(crumb: breadcrumb)
        #endif
    }

    func updateUserId(_ userId: String?) {
        #if canImport(Sentry)
        SentrySDK.configureScope { scope in
            if let userId = userId, !userId.isEmpty {
                scope.setTag(value: userId, key: "userId")
            } else {
                scope.setTag(value: "none", key: "userId")
            }
        }
        #endif
    }
}
