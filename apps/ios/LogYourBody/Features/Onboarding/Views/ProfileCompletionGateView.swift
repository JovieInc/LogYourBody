import SwiftUI

struct ProfileCompletionGateView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = OnboardingFlowViewModel()

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
