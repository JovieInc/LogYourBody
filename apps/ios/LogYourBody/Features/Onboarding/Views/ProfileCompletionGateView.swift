import SwiftUI

@MainActor
enum ProfileCompletionGatePolicy {
    static func makeViewModel() -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(includesFirstPhotoStep: false)
    }
}

struct ProfileCompletionGateView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel: OnboardingFlowViewModel

    init(viewModel: OnboardingFlowViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ProfileCompletionGatePolicy.makeViewModel())
    }

    var body: some View {
        BodyScoreProfileDetailsView(viewModel: viewModel)
            .environmentObject(authManager)
            .onAppear {
                if viewModel.currentStep != .profileDetails {
                    viewModel.currentStep = .profileDetails
                }
            }
    }
}

#Preview {
    ProfileCompletionGateView()
        .environmentObject(AuthManager.shared)
}
