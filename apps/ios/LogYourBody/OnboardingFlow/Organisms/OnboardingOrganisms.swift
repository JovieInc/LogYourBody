import SwiftUI

struct OnboardingScreenContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(24)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

struct LoadingStatusView: View {
    let title: String
    let statusMessages: [String]
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.primary)
                .scaleEffect(1.2)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                Text(statusMessages[currentIndex])
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .onAppear {
            guard statusMessages.count > 1 else { return }
            Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { timer in
                currentIndex = (currentIndex + 1) % statusMessages.count
                if currentIndex == statusMessages.count - 1 {
                    timer.invalidate()
                }
            }
        }
    }
}
