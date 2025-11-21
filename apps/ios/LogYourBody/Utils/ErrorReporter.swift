import Foundation

struct ErrorContext {
    let feature: String
    let operation: String?
    let screen: String?
    let userId: String?
}

final class ErrorReporter {
    static let shared = ErrorReporter()

    private init() {}

    func capture(_ error: AppError, context: ErrorContext) {
        log(error: error, context: context)
    }

    func captureNonFatal(_ error: Error, context: ErrorContext) {
        let wrapped = AppError.unexpected(context: context.operation ?? context.feature, underlying: error)
        log(error: wrapped, context: context)
    }

    private func log(error: AppError, context: ErrorContext) {
        let logger = loggerForFeature(context.feature)
        let message = contextDescription(context: context)
        logger.error("Error: \(error.localizedDescription). \(message)")
    }

    private func loggerForFeature(_ feature: String) -> AppLogger {
        switch feature {
        case "auth":
            return .auth
        case "sync":
            return .sync
        case "supabase":
            return .supabase
        case "photos":
            return .photos
        case "coreData":
            return .coreData
        default:
            return .ui
        }
    }

    private func contextDescription(context: ErrorContext) -> String {
        var parts: [String] = []
        parts.append("feature=\(context.feature)")
        if let operation = context.operation {
            parts.append("operation=\(operation)")
        }
        if let screen = context.screen {
            parts.append("screen=\(screen)")
        }
        if let userId = context.userId {
            parts.append("userId=\(userId)")
        }
        return parts.joined(separator: " ")
    }
}
