import SwiftUI

// MARK: - Typography Tokens

enum OnboardingTypography {
    private static let theme = DefaultTheme()

    static var title: Font { theme.typography.headlineMedium }
    static var headline: Font { theme.typography.headlineSmall }
    static var body: Font { theme.typography.bodyMedium }
    static var caption: Font { theme.typography.captionLarge }
}

struct OnboardingTitleText: View {
    @Environment(\.theme)
    private var theme

    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(theme.typography.headlineMedium)
            .multilineTextAlignment(alignment)
            .foregroundStyle(theme.colors.text)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OnboardingSubtitleText: View {
    @Environment(\.theme)
    private var theme

    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(theme.typography.bodyMedium)
            .foregroundStyle(theme.colors.textSecondary)
            .multilineTextAlignment(alignment)
    }
}

struct OnboardingCaptionText: View {
    @Environment(\.theme)
    private var theme

    let text: String
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(theme.typography.captionLarge)
            .foregroundStyle(theme.colors.textTertiary)
            .multilineTextAlignment(alignment)
    }
}

// MARK: - Buttons

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme)
    private var theme

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(theme.typography.labelLarge)
            .frame(maxWidth: .infinity)
            .frame(minHeight: JovieTokens.controlHeight)
            .foregroundStyle(isEnabled ? theme.colors.background : theme.colors.background.opacity(0.55))
            .background(
                Capsule(style: .continuous)
                    .fill(theme.colors.text.opacity(buttonOpacity(isPressed: configuration.isPressed)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(theme.colors.text.opacity(0.16))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : theme.animation.fast, value: configuration.isPressed)
    }

    private func buttonOpacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.35 }
        return isPressed ? 0.92 : 1
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme)
    private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(theme.typography.labelLarge)
            .frame(maxWidth: .infinity)
            .frame(minHeight: JovieTokens.compactControlHeight)
            .foregroundStyle(theme.colors.text)
            .systemBGlassSurface(
                cornerRadius: theme.radius.button,
                tint: theme.colors.text,
                tintOpacity: configuration.isPressed ? 0.05 : 0.035,
                borderColor: theme.colors.border,
                borderOpacity: 0.65
            )
            .animation(reduceMotion ? nil : theme.animation.fast, value: configuration.isPressed)
    }
}

struct OnboardingTextButton: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.typography.labelMedium)
                .foregroundStyle(theme.colors.primary)
                .padding(.vertical, 8)
        }
        .jovieTouchTarget()
    }
}

// MARK: - Supporting Atoms

struct OnboardingBulletItem: Identifiable, Hashable {
    let id = UUID()
    let iconName: String
    let text: String
}

struct OnboardingIconBullet: View {
    @Environment(\.theme)
    private var theme

    let item: OnboardingBulletItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.colors.primary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(theme.colors.primary.opacity(0.15))
                )

            Text(item.text)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.text)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}

struct OnboardingBadge: View {
    @Environment(\.theme)
    private var theme

    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(theme.typography.labelSmall)
            .foregroundStyle(theme.colors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.colors.primary.opacity(0.12))
            )
    }
}

struct OnboardingCard<Content: View>: View {
    @Environment(\.theme)
    private var theme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .systemBGlassSurface(
                cornerRadius: theme.radius.card,
                tint: theme.colors.text,
                tintOpacity: 0.04,
                borderColor: theme.colors.border,
                borderOpacity: 0.7,
                shadowOpacity: 0.18,
                shadowRadius: 14,
                shadowY: 8
            )
    }
}

// MARK: - FFMI Helper

struct FFMIInfoContent: View {
    @Environment(\.theme)
    private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's FFMI?")
                .font(theme.typography.headlineSmall)
                .foregroundStyle(theme.colors.text)

            Text("Fat-Free Mass Index compares your lean mass to your height, so bigger frames don’t get penalized.")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)

            Text("We pair FFMI with body fat and percentile bands to surface your Body Score and coaching cues.")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

struct FFMIInfoLink: View {
    @Environment(\.theme)
    private var theme

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
                        .font(.system(.footnote, design: .default).weight(.semibold))
                    Text("What's FFMI?")
                        .font(theme.typography.labelMedium)
                }
                .foregroundStyle(Color.jovieAction)
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
                .background(Color.jovieCanvas.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            isPresenting = false
                        }
                        .foregroundStyle(Color.jovieAction)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }
}
