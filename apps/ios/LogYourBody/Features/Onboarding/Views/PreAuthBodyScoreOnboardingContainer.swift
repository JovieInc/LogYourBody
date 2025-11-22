import SwiftUI

@MainActor
struct PreAuthBodyScoreOnboardingContainer: View {
    @Environment(\.dismiss) private var dismiss

    private let onCompleted: () -> Void

    init(onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            BodyScoreOnboardingFlowView(
                viewModel: OnboardingFlowViewModel(entryContext: .preAuth)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("preAuthOnboardingCompleted"))) { _ in
            dismiss()
            onCompleted()
        }
    }
}

#Preview {
    PreAuthBodyScoreOnboardingContainer(onCompleted: {})
        .environmentObject(AuthManager.shared)
        .environmentObject(RevenueCatManager.shared)
}
