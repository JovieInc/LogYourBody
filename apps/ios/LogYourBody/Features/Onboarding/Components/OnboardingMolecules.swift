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
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    if let subtitle {
                        Text(subtitle)
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.appTextSecondary.opacity(0.6))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.appPrimary.opacity(0.18) : Color.appCard.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? Color.appPrimary : Color.appBorder.opacity(0.6), lineWidth: isSelected ? 2 : 1)
                    )
            )
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented Control

struct OnboardingSegmentedControl<Option: Hashable & CustomStringConvertible>: View {
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }, label: {
                    Text(option.description)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selection == option ? Color.white : Color.appText)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selection == option ? Color.appPrimary : Color.appCard.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selection == option ? Color.appPrimary : Color.appBorder.opacity(0.6))
                        )
                })
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.appCard.opacity(0.4))
        )
    }
}

struct OnboardingInfoRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 2)

            Text(text)
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Input Rows

struct OnboardingTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isFocused ? Color.appPrimary : Color.appBorder.opacity(0.6), lineWidth: 1)
                )
        }
    }
}

struct OnboardingValueRow: View {
    let label: String
    let value: String
    let helper: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.appTextSecondary)

                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.appText)

                if let helper {
                    Text(helper)
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextTertiary)
                }
            }

            Spacer()

            if let actionTitle, let action {
                Button(action: action, label: {
                    Text(actionTitle)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.appPrimary)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.appBorder.opacity(0.4))
        )
    }
}

// MARK: - Form Section Wrapper

struct OnboardingFormSection<Content: View>: View {
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
                    .foregroundStyle(Color.appText)
            }

            if let caption {
                Text(caption)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }

            VStack(spacing: 16) {
                content
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressIndicator: View {
    let context: OnboardingFlowViewModel.ProgressContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(context.currentIndex) of \(context.totalCount)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.appTextSecondary)

                Spacer()

                Text(context.label)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appCard.opacity(0.45))

                    Capsule()
                        .fill(Color.appPrimary)
                        .frame(
                            width: min(
                                max(geometry.size.width * context.fractionComplete, 12),
                                geometry.size.width
                            )
                        )
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Page Template

struct OnboardingPageTemplate<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    var showsBackButton: Bool
    var onBack: (() -> Void)?
    var content: Content
    var footer: Footer
    var progress: OnboardingFlowViewModel.ProgressContext?

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        progress: OnboardingFlowViewModel.ProgressContext? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.content = content()
        self.footer = footer()
        self.progress = progress
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.appBackground, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    content

                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsBackButton {
                Button(action: {
                    onBack?()
                }, label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appText)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
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
