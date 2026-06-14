import SwiftUI

struct BodyScoreLoadingView: View {
    @Environment(\.theme)
    private var theme

    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.colors.background, theme.colors.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))
                    .scaleEffect(1.3)

                OnboardingTitleText(text: "Crunching your numbers…", alignment: .center)

                OnboardingSubtitleText(text: "Pulling lean mass, FFMI, and percentile bands.", alignment: .center)
            }
            .padding()
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
