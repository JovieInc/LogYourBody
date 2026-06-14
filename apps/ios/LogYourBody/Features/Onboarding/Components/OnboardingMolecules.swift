import SwiftUI

// MARK: - Bullet Lists

struct OnboardingBulletList: View {
    let items: [OnboardingBulletItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                OnboardingIconBullet(item: item)
            }
        }
    }
}

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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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
            .padding(20)
            .systemBGlassSurface(
                cornerRadius: 20,
                tint: isSelected ? theme.colors.primary : theme.colors.text,
                tintOpacity: isSelected ? 0.16 : 0.035,
                borderColor: isSelected ? theme.colors.primary : theme.colors.border,
                borderOpacity: isSelected ? 0.85 : 0.65,
                borderWidth: isSelected ? 2 : 1
            )
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented Control

struct OnboardingSegmentedControl<Option: Hashable & CustomStringConvertible>: View {
    @Environment(\.theme)
    private var theme

    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }, label: {
                    Text(option.description)
                        .font(theme.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selection == option ? theme.colors.text : theme.colors.textSecondary)
                        .systemBGlassSurface(
                            cornerRadius: 14,
                            tint: selection == option ? theme.colors.primary : theme.colors.text,
                            tintOpacity: selection == option ? 0.28 : 0.02,
                            borderColor: selection == option ? theme.colors.primary : theme.colors.border,
                            borderOpacity: selection == option ? 0.9 : 0.5
                        )
                })
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .systemBGlassSurface(
            cornerRadius: 18,
            tint: theme.colors.text,
            tintOpacity: 0.02,
            borderColor: theme.colors.border,
            borderOpacity: 0.45
        )
    }
}

struct OnboardingInfoRow: View {
    @Environment(\.theme)
    private var theme

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .systemBGlassSurface(
                    cornerRadius: theme.radius.input,
                    tint: isFocused ? theme.colors.primary : theme.colors.text,
                    tintOpacity: isFocused ? 0.07 : 0.03,
                    borderColor: isFocused ? theme.colors.primary : theme.colors.border,
                    borderOpacity: isFocused ? 0.9 : 0.65
                )
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
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
            }
        }
        .padding(20)
        .systemBGlassSurface(
            cornerRadius: 20,
            tint: theme.colors.text,
            tintOpacity: 0.035,
            borderColor: theme.colors.border,
            borderOpacity: 0.55
        )
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
        VStack(alignment: .leading, spacing: 12) {
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

            VStack(spacing: 16) {
                content
            }
            .padding(20)
            .systemBGlassSurface(
                cornerRadius: 24,
                tint: theme.colors.text,
                tintOpacity: 0.035,
                borderColor: theme.colors.border,
                borderOpacity: 0.6
            )
        }
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressIndicator: View {
    @Environment(\.theme)
    private var theme

    let context: OnboardingFlowViewModel.ProgressContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(context.currentIndex) of \(context.totalCount)")
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
            LinearGradient(
                colors: [theme.colors.background, theme.colors.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, showsCTA ? 24 : 40)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("onboarding_scaffold_scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsCTA {
                ctaContainer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("onboarding_scaffold")
    }

    private var ctaContainer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.colors.text.opacity(0.08))
                .frame(height: 1)

            cta
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
        .background(
            theme.colors.background
                .opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityIdentifier("onboarding_fixed_cta_container")
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
    var hasFooter: Bool

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        progress: OnboardingFlowViewModel.ProgressContext? = nil,
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
        self.hasFooter = true
    }

    var body: some View {
        OnboardingScaffold(showsCTA: hasFooter) {
            contentStack
        } cta: {
            footer
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsBackButton {
                Button(action: {
                    onBack?()
                }, label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.text)
                        .padding(10)
                        .systemBGlassSurface(
                            cornerRadius: 14,
                            tint: theme.colors.text,
                            tintOpacity: 0.05,
                            borderColor: theme.colors.border,
                            borderOpacity: 0.5
                        )
                })
                .buttonStyle(.plain)
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
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.content = content()
        self.footer = EmptyView()
        self.progress = progress
        self.hasFooter = false
    }
}
