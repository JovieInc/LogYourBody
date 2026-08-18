import SwiftUI

// MARK: - Option Buttons

struct OnboardingOptionButton: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            HStack(alignment: .center, spacing: theme.spacing.sm) {
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(title)
                        .font(OnboardingTypography.headline)
                        .foregroundStyle(theme.colors.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        .layoutPriority(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary.opacity(0.6))
            }
            .padding(theme.spacing.md)
            .background(
                isSelected ? theme.colors.surfaceSecondary : theme.colors.surface,
                in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .stroke(
                        isSelected ? theme.colors.text.opacity(0.9) : theme.colors.border.opacity(JovieTokens.hairlineOpacity),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        })
        .buttonStyle(.plain)
        .jovieTouchTarget()
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Segmented Control

struct OnboardingSegmentedControl<Option: Hashable & CustomStringConvertible>: View {
    @Environment(\.theme)
    private var theme

    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }, label: {
                    Text(option.description)
                        .font(theme.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: JovieTokens.compactControlHeight)
                        .foregroundStyle(selection == option ? theme.colors.text : theme.colors.textSecondary)
                        .systemBGlassSurface(
                            cornerRadius: JovieTokens.controlHeight,
                            tint: selection == option ? theme.colors.primary : theme.colors.text,
                            tintOpacity: selection == option ? 0.22 : 0.03,
                            borderColor: selection == option ? theme.colors.primary : theme.colors.border,
                            borderOpacity: selection == option ? 0.9 : 0.45
                        )
                        .clipShape(Capsule(style: .continuous))
                })
                .buttonStyle(.plain)
                .jovieTouchTarget()
                .accessibilityValue(selection == option ? "Selected" : "Not selected")
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}

struct OnboardingInfoRow: View {
    @Environment(\.theme)
    private var theme

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.xs) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 2)

            Text(text)
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Input Rows

struct OnboardingTextFieldRow: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .padding(.horizontal, theme.spacing.sm)
                .frame(minHeight: JovieTokens.controlHeight)
                .systemBGlassSurface(
                    cornerRadius: JovieTokens.controlHeight,
                    tint: isFocused ? theme.colors.primary : theme.colors.text,
                    tintOpacity: isFocused ? 0.07 : 0.03,
                    borderColor: isFocused ? theme.colors.primary : theme.colors.border,
                    borderOpacity: isFocused ? 0.9 : 0.65
                )
                .clipShape(Capsule(style: .continuous))
        }
    }
}

struct OnboardingValueRow: View {
    @Environment(\.theme)
    private var theme

    let label: String
    let value: String
    let helper: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(label.uppercased())
                    .font(theme.typography.labelSmall)
                    .foregroundStyle(theme.colors.textSecondary)

                Text(value)
                    .font(theme.typography.headlineSmall)
                    .foregroundStyle(theme.colors.text)

                if let helper {
                    Text(helper)
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            Spacer()

            if let actionTitle, let action {
                Button(action: action, label: {
                    Text(actionTitle)
                        .font(theme.typography.labelMedium)
                        .foregroundStyle(theme.colors.primary)
                })
                .buttonStyle(.plain)
                .jovieTouchTarget()
            }
        }
        .padding(.vertical, theme.spacing.xs)
    }
}

// MARK: - Form Section Wrapper

struct OnboardingFormSection<Content: View>: View {
    @Environment(\.theme)
    private var theme

    let title: String?
    let caption: String?
    let content: Content

    init(title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if let title {
                Text(title)
                    .font(OnboardingTypography.headline)
                    .foregroundStyle(theme.colors.text)
            }

            if let caption {
                Text(caption)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            VStack(spacing: theme.spacing.md) {
                content
            }
        }
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressIndicator: View {
    @Environment(\.theme)
    private var theme

    let context: OnboardingFlowViewModel.ProgressContext

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("\(context.label) · \(Int((context.fractionComplete * 100).rounded()))%")
                .font(theme.typography.labelSmall)
                .foregroundStyle(theme.colors.textSecondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.colors.surfaceTertiary.opacity(0.55))

                    Capsule()
                        .fill(theme.colors.primary)
                        .frame(
                            width: min(
                                max(geometry.size.width * context.fractionComplete, 12),
                                geometry.size.width
                            )
                        )
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Page Template

struct OnboardingScaffold<Content: View, CTA: View>: View {
    @Environment(\.theme)
    private var theme

    let showsCTA: Bool
    let content: Content
    let cta: CTA

    init(
        showsCTA: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder cta: () -> CTA
    ) {
        self.showsCTA = showsCTA
        self.content = content()
        self.cta = cta()
    }

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.top, theme.spacing.xs)
                    .padding(.bottom, showsCTA ? theme.spacing.lg : theme.spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .accessibilityIdentifier("onboarding_scaffold_scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsCTA {
                ctaContainer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var ctaContainer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.colors.border.opacity(JovieTokens.hairlineOpacity))
                .frame(height: 1)

            cta
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, theme.spacing.sm)
        }
        .background(
            theme.colors.background
                .opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct OnboardingPageTemplate<Content: View, Footer: View>: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let subtitle: String?
    var showsBackButton: Bool
    var onBack: (() -> Void)?
    var content: Content
    var footer: Footer
    var progress: OnboardingFlowViewModel.ProgressContext?
    var screen: WorldClassScreen?
    var hasFooter: Bool

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        progress: OnboardingFlowViewModel.ProgressContext? = nil,
        screen: WorldClassScreen? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.content = content()
        self.footer = footer()
        self.progress = progress
        self.screen = screen
        self.hasFooter = true
    }

    var body: some View {
        Group {
            if let screen {
                scaffold.worldClassScreen(screen)
            } else {
                scaffold
            }
        }
    }

    private var scaffold: some View {
        OnboardingScaffold(showsCTA: hasFooter) {
            contentStack
        } cta: {
            footer
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            header

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            if showsBackButton {
                Button(action: {
                    onBack?()
                }, label: {
                    Image(systemName: "chevron.left")
                        .font(theme.typography.labelLarge)
                        .foregroundStyle(theme.colors.text)
                        .padding(theme.spacing.xs)
                        .systemBGlassSurface(
                            cornerRadius: JovieTokens.controlHeight,
                            tint: theme.colors.text,
                            tintOpacity: 0.05,
                            borderColor: theme.colors.border,
                            borderOpacity: 0.5
                        )
                        .clipShape(Circle())
                })
                .buttonStyle(.plain)
                .jovieTouchTarget()
            }

            if let progress {
                OnboardingProgressIndicator(context: progress)
            }

            OnboardingTitleText(text: title, alignment: .leading)

            if let subtitle {
                OnboardingSubtitleText(text: subtitle, alignment: .leading)
            }
        }
    }
}

extension OnboardingPageTemplate where Footer == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        progress: OnboardingFlowViewModel.ProgressContext? = nil,
        screen: WorldClassScreen? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.content = content()
        self.footer = EmptyView()
        self.progress = progress
        self.screen = screen
        self.hasFooter = false
    }
}
