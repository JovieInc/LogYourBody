import SwiftUI

// MARK: - Typography Tokens

enum OnboardingTypography {
    static var title: Font { .system(.title2, design: .rounded).weight(.semibold) }
    static var headline: Font { .system(.title3, design: .rounded).weight(.semibold) }
    static var body: Font { .system(.body, design: .rounded) }
    static var caption: Font { .system(.footnote, design: .rounded) }
}

struct OnboardingTitleText: View {
    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(OnboardingTypography.title)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Color.appText)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OnboardingSubtitleText: View {
    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(OnboardingTypography.body)
            .foregroundStyle(Color.appTextSecondary)
            .multilineTextAlignment(alignment)
    }
}

struct OnboardingCaptionText: View {
    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(OnboardingTypography.caption)
            .foregroundStyle(Color.appTextTertiary)
            .multilineTextAlignment(alignment)
    }
}

// MARK: - Buttons

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appPrimary.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.appText)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.appBorder.opacity(0.5))
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OnboardingTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(Color.appPrimary)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - Supporting Atoms

struct OnboardingBulletItem: Identifiable, Hashable {
    let id = UUID()
    let iconName: String
    let text: String
}

struct OnboardingIconBullet: View {
    let item: OnboardingBulletItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.appPrimary.opacity(0.15))
                )

            Text(item.text)
                .font(OnboardingTypography.body)
                .foregroundStyle(Color.appText)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}

struct OnboardingBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appPrimary.opacity(0.12))
            )
    }
}

struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.06))
            )
    }
}

// MARK: - FFMI Helper

struct FFMIInfoContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's FFMI?")
                .font(OnboardingTypography.headline)
                .foregroundStyle(Color.appText)

            Text("Fat-Free Mass Index compares your lean mass to your height, so bigger frames don’t get penalized.")
                .font(OnboardingTypography.body)
                .foregroundStyle(Color.appTextSecondary)

            Text("We pair FFMI with body fat and percentile bands to surface your Body Score and coaching cues.")
                .font(OnboardingTypography.body)
                .foregroundStyle(Color.appTextSecondary)
        }
    }
}

struct FFMIInfoLink: View {
    @State private var isPresenting = false

    var body: some View {
        Button(
            action: {
                isPresenting = true
                HapticManager.shared.selection()
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("What's FFMI?")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.appPrimary)
                .padding(.vertical, 4)
            }
        )
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresenting) {
            NavigationStack {
                ScrollView {
                    FFMIInfoContent()
                        .padding(24)
                }
                .background(Color.appBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            isPresenting = false
                        }
                        .foregroundStyle(Color.appPrimary)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }
}
