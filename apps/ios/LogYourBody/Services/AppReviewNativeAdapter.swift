import JovieKit
import StoreKit
import SwiftUI
import UIKit

extension BodyRecordReviewConsumer {
    static let shared: BodyRecordReviewConsumer = {
        let url = URL.applicationSupportDirectory
            .appendingPathComponent("AppReview", isDirectory: true)
            .appendingPathComponent("ledger.json")
        let file = AppReviewLedgerFile(url: url)
        return BodyRecordReviewConsumer(coordinator: AppReview.Coordinator(load: file.load, save: file.save))
    }()
}

/// StoreKit is invoked only in the window that hosts the product surface.
/// A void invocation is not evidence of display, dismissal or a submitted review.
@MainActor
struct AppReviewNativeAdapter {
    var invoke: (UIWindowScene) -> Void = { AppStore.requestReview(in: $0) }

    func context(
        window: UIWindow?, isOnline: Bool, isAppStoreBuild: Bool, now: Date = Date()
    ) -> AppReview.Context {
        let active = window?.windowScene?.activationState == .foregroundActive &&
            UIApplication.shared.applicationState == .active
        let root = window?.rootViewController
        let quiet = window?.isKeyWindow == true && root != nil &&
            root?.presentedViewController == nil && root?.transitionCoordinator == nil &&
            root?.isBeingPresented == false && root?.isBeingDismissed == false &&
            window.map { !hasInteraction(in: $0) } == true
        return AppReview.Context(
            now: now,
            isAppStoreBuild: isAppStoreBuild,
            isForegroundActive: active,
            hasExperiencedValue: true,
            isQuietMoment: quiet,
            isOnline: isOnline,
            hasBlockingActivity: !quiet
        )
    }

    func isAppStoreBuild() async -> Bool {
        #if DEBUG
        return false
        #else
        // Read the verified distribution only. Never refresh, request sign-in,
        // retain transaction details, or use commerce history as review eligibility.
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else { return false }
            return transaction.environment == .production
        } catch {
            return false
        }
        #endif
    }

    private func hasInteraction(in view: UIView) -> Bool {
        if view.isFirstResponder { return true }
        if let scrollView = view as? UIScrollView,
           scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating { return true }
        if view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
            return true
        }
        return view.subviews.contains { hasInteraction(in: $0) }
    }
}

private final class AppReviewWindowReference: ObservableObject {
    weak var window: UIWindow?
}

private struct AppReviewWindowProbe: UIViewRepresentable {
    let reference: AppReviewWindowReference

    func makeUIView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.reference = reference
        return view
    }

    func updateUIView(_ uiView: WindowProbe, context: Context) {}

    final class WindowProbe: UIView {
        weak var reference: AppReviewWindowReference?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reference?.window = window
        }
    }
}

struct BodyRecordReviewPresentation: ViewModifier {
    let currentOwnerID: String?
    let isProductReady: Bool
    let isOnline: Bool
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var consumer = BodyRecordReviewConsumer.shared
    @StateObject private var windowReference = AppReviewWindowReference()
    @State private var gateRevision = 0

    private struct TaskIdentity: Equatable {
        let candidate: BodyRecordReviewConsumer.Candidate?
        let ownerID: String?
        let ready: Bool
        let online: Bool
        let active: Bool
        let gateRevision: Int
    }

    func body(content: Content) -> some View {
        content
            .background {
                AppReviewWindowProbe(reference: windowReference)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: currentOwnerID) { _, _ in consumer.discardForAccountChange() }
            .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
                gateRevision += 1
            }
            .task(id: TaskIdentity(
                candidate: consumer.candidate, ownerID: currentOwnerID, ready: isProductReady,
                online: isOnline, active: scenePhase == .active, gateRevision: gateRevision
            )) {
                guard isProductReady, isOnline, scenePhase == .active else { return }
                guard AppServicePorts.analyticsTracker.isFeatureEnabled(
                    flagKey: BodyRecordReviewConsumer.gateKey
                ) else { return }
                let adapter = AppReviewNativeAdapter()
                let isAppStoreBuild = await adapter.isAppStoreBuild()
                guard !Task.isCancelled else { return }
                while consumer.candidate != nil {
                    // Let the success UI and sheet dismissal settle; recheck the
                    // actual scene and interaction each time, never cache readiness.
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard !Task.isCancelled else { return }
                    guard let window = windowReference.window, let scene = window.windowScene else { continue }
                    let policy = AppReview.Policy(enabled: AppServicePorts.analyticsTracker.isFeatureEnabled(
                        flagKey: BodyRecordReviewConsumer.gateKey
                    ))
                    let decision = consumer.consider(
                        currentOwnerID: currentOwnerID,
                        context: adapter.context(
                            window: window, isOnline: isOnline, isAppStoreBuild: isAppStoreBuild
                        ),
                        policy: policy,
                        request: { adapter.invoke(scene) }
                    )
                    if decision?.reason == .disabled { return }
                }
            }
    }
}
