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

                OnboardingTitleText(text: "Building your Body Score", alignment: .center)

                OnboardingSubtitleText(
                    text: "Combining lean mass, body fat, and validated reference ranges.",
                    alignment: .center
                )
            }
            .padding(JovieTokens.screenInset)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Calculating your Body Score")
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
