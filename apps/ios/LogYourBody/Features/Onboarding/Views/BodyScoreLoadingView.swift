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

                OnboardingTitleText(text: "Crunching your numbers…", alignment: .center)

                OnboardingSubtitleText(text: "Pulling lean mass, FFMI, and percentile bands.", alignment: .center)
            }
            .padding(JovieTokens.screenInset)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Calculating your Body Score")
            .accessibilityValue("Please wait")
        }
        .task {
            await viewModel.calculateScoreIfNeeded()
        }
    }
}

#Preview {
    BodyScoreLoadingView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
