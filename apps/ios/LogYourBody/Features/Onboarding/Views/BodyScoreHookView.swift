import SwiftUI

struct BodyScoreHookView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @Environment(\.dismiss) private var dismiss

    private let bulletItems: [OnboardingBulletItem] = [
        .init(iconName: "scalemass", text: "Your latest weight"),
        .init(iconName: "percent", text: "A measured or estimated body-fat value"),
        .init(iconName: "ruler", text: "Your height for a frame-adjusted comparison")
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "See what’s changing.",
            subtitle: "Use weight, body fat, and height to build your first Body Score in about 60 seconds.",
            showsBackButton: false,
            progress: viewModel.progress(for: .hook),
            screen: .bodyScoreIntro
        ) {
            VStack(spacing: JovieTokens.sectionGap) {
                BodyScoreContourField()
                    .frame(height: 190)

                OnboardingBulletList(items: bulletItems)
            }
        } footer: {
            VStack(spacing: 12) {
                Button {
                    viewModel.goToNextStep()
                } label: {
                    Text("Build my Body Score")
                }
                .accessibilityIdentifier("body_score_onboarding_start_button")
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

private struct BodyScoreContourField: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
            let maximum = min(size.width, size.height) * 0.82

            for ring in 0..<9 {
                let progress = CGFloat(ring) / 8
                let width = maximum * (0.2 + progress * 0.8)
                let height = width * (0.58 + progress * 0.18)
                let rect = CGRect(
                    x: center.x - width / 2,
                    y: center.y - height / 2,
                    width: width,
                    height: height
                )
                let color = ring.isMultiple(of: 2) ? theme.colors.info : theme.colors.accentPink
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.14 + Double(8 - ring) * 0.016)),
                    lineWidth: ring == 0 ? 1.5 : 1
                )
            }
        }
        .background {
            RadialGradient(
                colors: [theme.colors.info.opacity(JovieTokens.ambientAccentOpacity), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 150
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BodyScoreHookView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
