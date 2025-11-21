import SwiftUI

struct BodyScoreHookView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private let bulletItems: [OnboardingBulletItem] = [
        .init(iconName: "figure.strengthtraining.traditional", text: "Unlock your Body Score in under 60 seconds."),
        .init(iconName: "bolt.heart", text: "See how your muscle, body fat, and FFMI stack up."),
        .init(iconName: "lock.open.display", text: "Preview the experience before creating an account.")
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "Build a dialed-in body.",
            subtitle: "Get your Body Score in under a minute.",
            showsBackButton: false
        ) {
            VStack(spacing: 32) {
                OnboardingBadge(text: "Body Score Early Access")

                VStack(alignment: .leading, spacing: 20) {
                    Text("You bring height, weight, and a rough body fat read. We highlight what’s working and what’s not.")
                        .font(OnboardingTypography.body)
                        .foregroundStyle(Color.appTextSecondary)

                    OnboardingBulletList(items: bulletItems)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary.opacity(0.25), Color.appCard.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08))
                )

                VStack(spacing: 16) {
                    Button("See my score") {
                        viewModel.goToNextStep()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button("I already have an account") {
                        NotificationCenter.default.post(name: Notification.Name("showLoginFromOnboarding"), object: nil)
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        }
    }
}

#Preview {
    BodyScoreHookView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
