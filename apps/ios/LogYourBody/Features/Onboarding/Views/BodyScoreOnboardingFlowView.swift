import SwiftUI

@MainActor
struct BodyScoreOnboardingFlowView: View {
    @StateObject private var viewModel: OnboardingFlowViewModel
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var hasTrackedOnboardingStart = false

    @MainActor
    init(viewModel: OnboardingFlowViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? OnboardingFlowViewModel())
    }

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .hook:
                BodyScoreHookView(viewModel: viewModel)
            case .basics:
                BodyScoreBasicsView(viewModel: viewModel)
            case .height:
                BodyScoreHeightView(viewModel: viewModel)
            case .healthConnect:
                BodyScoreHealthConnectView(viewModel: viewModel)
            case .healthConfirmation:
                BodyScoreHealthConfirmationView(viewModel: viewModel)
            case .manualWeight:
                BodyScoreManualWeightView(viewModel: viewModel)
            case .bodyFatChoice:
                BodyScoreBodyFatChoiceView(viewModel: viewModel)
            case .bodyFatNumeric:
                BodyScoreBodyFatNumericView(viewModel: viewModel)
            case .bodyFatVisual:
                BodyScoreBodyFatVisualView(viewModel: viewModel)
            case .loading:
                BodyScoreLoadingView(viewModel: viewModel)
            case .bodyScore:
                BodyScoreRevealView(viewModel: viewModel)
            case .emailCapture:
                BodyScoreEmailCaptureView(viewModel: viewModel)
            case .account:
                BodyScoreAccountCreationView(viewModel: viewModel)
                    .environmentObject(authManager)
            case .profileDetails:
                BodyScoreProfileDetailsView(viewModel: viewModel)
                    .environmentObject(authManager)
            case .paywall:
                PaywallView()
                    .environmentObject(authManager)
                    .environmentObject(revenueCatManager)
            }
        }
        .environmentObject(authManager)
        .onAppear {
            guard !hasTrackedOnboardingStart else { return }
            hasTrackedOnboardingStart = true
            AnalyticsService.shared.track(
                event: "onboarding_started",
                properties: [
                    "entry_context": viewModel.entryContext.analyticsContext
                ]
            )
        }
    }
}

#Preview {
    BodyScoreOnboardingFlowView()
        .environmentObject(AuthManager.shared)
        .environmentObject(RevenueCatManager.shared)
}
