import SwiftUI

struct BodyScoreLoadingView: View {
    @Environment(\.theme)
    private var theme

    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: JovieTokens.sectionGap) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .accessibilityHidden(true)

                OnboardingTitleText(text: "Splitting fat from muscle", alignment: .center)

                OnboardingSubtitleText(
                    text: "Working out your fat mass and lean mass.",
                    alignment: .center
                )
            }
            .padding(JovieTokens.screenInset)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Working out your fat and lean mass")
            .accessibilityValue("Please wait")
        }
        .task {
            await viewModel.calculateScoreIfNeeded()
        }
        .worldClassScreen(.calculation)
    }
}

#Preview {
    BodyScoreLoadingView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
