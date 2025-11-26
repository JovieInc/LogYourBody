import Foundation
import UIKit

#if canImport(Sentry)
import Sentry
#endif

@MainActor
final class BugReportManager: ObservableObject {
    static let shared = BugReportManager()

    static let maxMessageLength = 2000

    @Published var isPromptPresented = false
    @Published var isFormPresented = false
    @Published var message: String = ""
    @Published var includeScreenshot = true
    @Published private(set) var screenshotData: Data?

    @Published var isShakeToReportEnabled: Bool {
        didSet {
            if oldValue != isShakeToReportEnabled {
                userDefaults.set(isShakeToReportEnabled, forKey: Self.shakeToReportKey)
            }
        }
    }

    private let userDefaults: UserDefaults
    private static let shakeToReportKey = "shakeToReportBugEnabled"
    private var isCapturingScreenshot = false

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if userDefaults.object(forKey: Self.shakeToReportKey) == nil {
            self.isShakeToReportEnabled = true
        } else {
            self.isShakeToReportEnabled = userDefaults.bool(forKey: Self.shakeToReportKey)
        }
    }

    var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleShakeGesture() {
        #if canImport(Statsig)
        if !AnalyticsService.shared.isFeatureEnabled(flagKey: "bug_report_shake_v1") {
            return
        }
        #endif

        guard isShakeToReportEnabled else { return }
        guard !isPromptPresented, !isFormPresented else { return }
        guard !isCapturingScreenshot else { return }

        isCapturingScreenshot = true

        Task { [weak self] in
            guard let self else { return }
            let data = await Self.captureCurrentScreenshot()

            await MainActor.run {
                self.isCapturingScreenshot = false
                self.screenshotData = data
                self.includeScreenshot = data != nil
                self.message = ""
                self.isPromptPresented = true
            }
        }
    }

    func presentFormFromPrompt() {
        isPromptPresented = false
        isFormPresented = true
    }

    func cancel() {
        isFormPresented = false
        isPromptPresented = false
    }

    func submit() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let currentScreenshot = includeScreenshot ? screenshotData : nil
        let user = AuthManager.shared.currentUser
        let name = user?.displayName
        let email = user?.email

        var properties: [String: String] = [
            "has_screenshot": currentScreenshot != nil ? "true" : "false"
        ]

        if let id = user?.id {
            properties["user_id"] = id
        }

        AnalyticsService.shared.track(
            event: "bug_report_submitted",
            properties: properties
        )

        #if canImport(Sentry)
        let messageToSend = trimmed
        let nameToSend = name
        let emailToSend = email
        let screenshotToSend = currentScreenshot

        Task.detached(priority: .userInitiated) {
            let feedback = SentryFeedback(
                message: messageToSend,
                name: nameToSend,
                email: emailToSend,
                source: .custom,
                screenshot: screenshotToSend
            )
            SentrySDK.capture(feedback: feedback)
        }
        #endif

        isFormPresented = false
        isPromptPresented = false
        message = ""
    }

    private static func captureCurrentScreenshot() async -> Data? {
        let image = await MainActor.run { captureScreenshotImage() }
        guard let image else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = image.pngData()
                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    private static func captureScreenshotImage() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }

        let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        guard let window = keyWindow else {
            return nil
        }

        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let image = renderer.image { context in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        return image
    }
}
