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
            .jovieTouchTarget()
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
            .jovieTouchTarget()
            .foregroundStyle(theme.colors.text)
            .systemBGlassSurface(
                cornerRadius: JovieTokens.controlHeight,
                tint: theme.colors.text,
                tintOpacity: configuration.isPressed ? 0.05 : 0.035,
                borderColor: theme.colors.border,
                borderOpacity: 0.65
            )
            .clipShape(Capsule(style: .continuous))
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

/// The shared disclosure affordance for short onboarding explanations.
/// Keep the label, icon, hit target, and expanded state consistent across pages.
struct OnboardingDisclosureLink: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: "questionmark.circle")
                    .font(theme.typography.captionLarge.weight(.semibold))

                Text(title)
                    .font(theme.typography.captionLarge)
            }
            .foregroundStyle(theme.colors.primary)
        }
        .buttonStyle(.plain)
        .jovieTouchTarget()
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides more information." : "Shows more information.")
    }
}

// MARK: - Supporting Atoms

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
            .padding(theme.spacing.md)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .stroke(theme.colors.border.opacity(JovieTokens.hairlineOpacity), lineWidth: 1)
            }
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
