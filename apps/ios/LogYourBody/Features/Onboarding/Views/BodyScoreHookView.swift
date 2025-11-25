import SwiftUI

struct BodyScoreHookView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @Environment(\.dismiss) private var dismiss

    private let bulletItems: [OnboardingBulletItem] = [
        .init(iconName: "chart.xyaxis.line", text: "Track weight, body fat, and FFMI together."),
        .init(iconName: "person.3", text: "See where you land vs similar men."),
        .init(iconName: "arrow.triangle.2.circlepath", text: "Update your score anytime as you progress.")
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "Get your Body Score in 60 seconds.",
            subtitle: "See your muscle, body fat, and FFMI vs similar men.",
            showsBackButton: false,
            progress: viewModel.progress(for: .hook)
        ) {
            VStack(spacing: 24) {
                OnboardingBadge(text: "Body Score Early Access")

                OnboardingBulletList(items: bulletItems)

                VStack(spacing: 12) {
                    Button {
                        viewModel.goToNextStep()
                    } label: {
                        Text("Start my 60-sec Body Score")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    if viewModel.entryContext == .preAuth {
                        OnboardingTextButton(title: "I already have an account") {
                            dismiss()
                        }
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
