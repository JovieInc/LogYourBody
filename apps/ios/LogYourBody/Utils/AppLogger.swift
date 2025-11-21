import Foundation
import os

struct AppLogger {
    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "LogYourBody", category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func error(_ message: String, error: Error) {
        logger.error("\(message, privacy: .public) error=\(String(describing: error), privacy: .public)")
    }
}

extension AppLogger {
    static let auth = AppLogger(category: "auth")
    static let sync = AppLogger(category: "sync")
    static let supabase = AppLogger(category: "supabase")
    static let photos = AppLogger(category: "photos")
    static let coreData = AppLogger(category: "coreData")
    static let ui = AppLogger(category: "ui")
}
