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
            title: "Get your Body Score in 60 seconds.",
            subtitle: "See muscle, body fat, and FFMI vs people like you.",
            showsBackButton: false,
            progress: viewModel.progress(for: .hook)
        ) {
            VStack(spacing: 32) {
                OnboardingBadge(text: "Body Score Early Access")

                OnboardingCaptionText(text: "Beta feature • helps us fine-tune the score for you.", alignment: .leading)

                VStack(alignment: .leading, spacing: 20) {
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
                    Button {
                        viewModel.goToNextStep()
                    } label: {
                        Text("Start my 60-sec Body Score")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    OnboardingCaptionText(
                        text: "Takes under a minute. No account needed to see your score.",
                        alignment: .center
                    )
                    .foregroundStyle(Color.appTextSecondary)

                    OnboardingTextButton(title: "I already have an account") {
                        NotificationCenter.default.post(
                            name: Notification.Name("showLoginFromOnboarding"),
                            object: nil
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    BodyScoreHookView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
