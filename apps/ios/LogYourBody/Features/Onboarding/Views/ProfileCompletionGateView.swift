import SwiftUI

enum ProfileCompletionPolicy {
    static func isComplete(user: User?) -> Bool {
        guard let user else { return false }
        return isComplete(profile: user.profile, fallbackName: user.name)
    }

    static func isComplete(profile: UserProfile?, fallbackName: String?) -> Bool {
        guard let profile else { return false }

        let profileName = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDisplayName = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = profileName?.isEmpty == false ? profileName : fallbackDisplayName
        let hasName = !(displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDOB = profile.dateOfBirth != nil
        let hasHeight = (profile.height ?? 0) > 0
        let hasGender = !(profile.gender?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return hasName && hasDOB && hasHeight && hasGender
    }
}

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
                guard !viewModel.hasMarkedOnboardingComplete else { return }
                guard viewModel.currentStep != .paywall else { return }
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
