import Foundation

#if canImport(Sentry)
import Sentry
#endif

final class ErrorTrackingService {
    static let shared = ErrorTrackingService()

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
}
