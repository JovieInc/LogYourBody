import SwiftUI

/// Small atomic wrappers for consistent typography.
struct OnboardingTitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }
}

struct OnboardingSubtitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }
}

struct OnboardingCaptionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }
}
