import SwiftUI

struct BodyScoreLoadingView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.appBackground, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
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
