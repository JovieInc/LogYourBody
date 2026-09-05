//
// BaseButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - Button Configuration

struct ButtonConfiguration {
    var style: ButtonStyleVariant = .primary
    var size: ButtonSizeVariant = .medium
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var fullWidth: Bool = false
    var icon: String?
    var iconPosition: IconPosition = .leading
    var cornerRadius: CGFloat?
    var hapticFeedback: UIImpactFeedbackGenerator.FeedbackStyle? = .light

    enum ButtonStyleVariant {
        case primary
        case secondary
        case tertiary
        case destructive
        case ghost
        case social
        case custom(background: Color, foreground: Color)

        var backgroundColor: Color {
            switch self {
            case .primary: return .jovieAction
            case .secondary: return .appCard
            case .tertiary: return .appCard
            case .destructive: return Color.appError
            case .ghost: return .clear
            case .social: return .white
            case .custom(let bg, _): return bg
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .jovieActionText
            case .secondary: return .appText
            case .tertiary: return .appText
            case .destructive: return .white
            case .ghost: return .appTextSecondary
            case .social: return .black
            case .custom(_, let fg): return fg
            }
        }

        var borderColor: Color? {
            switch self {
            case .secondary: return .appBorder
            case .tertiary: return .appBorder
            default: return nil
            }
        }
    }

    enum ButtonSizeVariant {
        case small
        case medium
        case large
        case custom(height: CGFloat, padding: EdgeInsets, fontSize: CGFloat)

        var height: CGFloat {
            switch self {
            // ActionButton 32 / 510 / r999: one visible height for the CTA family.
            case .small, .medium, .large: return JovieTokens.actionControlHeight
            case .custom(let height, _, _): return height
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            case .medium: return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            case .large: return EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
            case .custom(_, let padding, _): return padding
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            case .custom(_, _, let fontSize): return fontSize
            }
        }

        var iconSize: CGFloat {
            fontSize * 0.9
        }
    }

    enum IconPosition {
        case leading
        case trailing
    }
}

// MARK: - Geometry policy

/// Source-bound contract for the locked ActionButton atom: a 32pt visible pill
/// whose hit area is expanded to at least 44pt without changing the visual.
enum BaseButtonGeometry {
    static func visibleHeight(for size: ButtonConfiguration.ButtonSizeVariant) -> CGFloat {
        size.height
    }

    static func tapTargetHeight(for size: ButtonConfiguration.ButtonSizeVariant) -> CGFloat {
        max(size.height, JovieTokens.minimumHitTarget)
    }
}

// MARK: - BaseButton

struct BaseButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnvironmentEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonConfiguration
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false

    private var isEnabled: Bool {
        configuration.isEnabled && !configuration.isLoading && isEnvironmentEnabled
    }

    private var usesCapsule: Bool {
        configuration.cornerRadius == nil
    }

    private var cornerRadius: CGFloat {
        configuration.cornerRadius ?? JovieTokens.controlHeight
    }

    private var labelTextStyle: Font.TextStyle {
        switch configuration.size {
        case .small:
            return .subheadline
        case .medium, .custom:
            return .body
        case .large:
            return .headline
        }
    }

    var body: some View {
        Button(action: handleTap, label: {
            buttonContent
                .frame(maxWidth: configuration.fullWidth ? .infinity : nil)
                .frame(minHeight: BaseButtonGeometry.visibleHeight(for: configuration.size))
                .padding(.horizontal, configuration.size.padding.leading)
                .background(backgroundView)
                .clipShape(buttonShape)
                .overlay(borderOverlay)
                .frame(minHeight: BaseButtonGeometry.tapTargetHeight(for: configuration.size))
                .contentShape(Rectangle())
                .scaleEffect(reduceMotion ? 1 : (isPressed || configuration.isLoading ? 0.96 : 1.0))
                .opacity(isEnabled ? 1.0 : 0.6)
                .animation(reduceMotion ? nil : .easeInOut(duration: JovieTokens.subtleDuration), value: isPressed)
                .animation(reduceMotion ? nil : .easeInOut(duration: JovieTokens.subtleDuration), value: configuration.isLoading)
        })
        .buttonStyle(PlainButtonStyle())
        .jovieTouchTarget()
        .disabled(!isEnabled)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }

    @ViewBuilder
    private var buttonContent: some View {
        if configuration.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: configuration.style.foregroundColor))
                .scaleEffect(0.8)
        } else {
            label()
                .font(.system(labelTextStyle, design: .default).weight(JovieTokens.actionLabelWeight))
                .foregroundColor(configuration.style.foregroundColor)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        configuration.style.backgroundColor
    }

    private var buttonShape: AnyShape {
        if usesCapsule {
            AnyShape(Capsule(style: .continuous))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let borderColor = configuration.style.borderColor {
            buttonShape.stroke(borderColor, lineWidth: 1)
        }
    }

    private func handleTap() {
        guard isEnabled else { return }

        if let feedbackStyle = configuration.hapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
            generator.impactOccurred()
        }

        action()
    }
}

// MARK: - Convenience Initializers

extension BaseButton where Label == AnyView {
    init(
        _ title: String,
        configuration: ButtonConfiguration = ButtonConfiguration(),
        action: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.action = action
        self.label = {
            AnyView(
                HStack(spacing: 8) {
                    if configuration.iconPosition == .leading, let icon = configuration.icon {
                        Image(systemName: icon)
                            .font(.system(size: configuration.size.iconSize))
                    }

                    Text(title)

                    if configuration.iconPosition == .trailing, let icon = configuration.icon {
                        Image(systemName: icon)
                            .font(.system(size: configuration.size.iconSize))
                    }
                }
            )
        }
    }
}

// MARK: - Icon-Only Button

struct BaseIconButton: View {
    let icon: String
    let size: CGFloat
    let style: IconButtonStyle
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum IconButtonStyle {
        case filled
        case outlined
        case plain

        var backgroundColor: Color {
            switch self {
            case .filled: return .appCard
            case .outlined, .plain: return .clear
            }
        }

        var borderColor: Color? {
            switch self {
            case .outlined: return .appBorder
            default: return nil
            }
        }
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }, label: {
            Image(systemName: icon)
                .font(.system(.body, design: .default).weight(.medium))
                .foregroundColor(.appText)
                .frame(width: max(size * 2, 32), height: max(size * 2, 32))
                .background(
                    Circle()
                        .fill(style.backgroundColor)
                        .overlay(
                            style.borderColor.map { color in
                                Circle().stroke(color, lineWidth: 1)
                            }
                        )
                )
                .jovieTouchTarget()
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1.0))
                .opacity(isEnabled ? 1.0 : 0.6)
                .animation(reduceMotion ? nil : .easeInOut(duration: JovieTokens.subtleDuration), value: isPressed)
        })
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Standard buttons
            Group {
                Text("Standard Buttons").font(.headline)
                BaseButton("Primary Button", action: {})
                BaseButton("Secondary", configuration: ButtonConfiguration(style: .secondary), action: {})
                BaseButton("Tertiary", configuration: ButtonConfiguration(style: .tertiary), action: {})
                BaseButton("Destructive", configuration: ButtonConfiguration(style: .destructive), action: {})
                BaseButton("Ghost", configuration: ButtonConfiguration(style: .ghost), action: {})
            }

            Divider()

            // With icons
            Group {
                Text("With Icons").font(.headline)
                BaseButton(
                    "Continue",
                    configuration: ButtonConfiguration(icon: "arrow.right", iconPosition: .trailing),
                    action: {}
                )
                BaseButton(
                    "Upload",
                    configuration: ButtonConfiguration(style: .secondary, icon: "arrow.up"),
                    action: {}
                )
            }

            Divider()

            // Sizes
            Group {
                Text("Sizes").font(.headline)
                BaseButton("Small", configuration: ButtonConfiguration(size: .small), action: {})
                BaseButton("Medium", configuration: ButtonConfiguration(size: .medium), action: {})
                BaseButton("Large", configuration: ButtonConfiguration(size: .large), action: {})
            }

            Divider()

            // States
            Group {
                Text("States").font(.headline)
                BaseButton("Loading", configuration: ButtonConfiguration(isLoading: true), action: {})
                BaseButton("Disabled", configuration: ButtonConfiguration(isEnabled: false), action: {})
                BaseButton("Full Width", configuration: ButtonConfiguration(fullWidth: true), action: {})
            }

            Divider()

            // Icon buttons
            Group {
                Text("Icon Buttons").font(.headline)
                HStack {
                    BaseIconButton(icon: "plus", size: 24, style: .filled, action: {})
                    BaseIconButton(icon: "camera", size: 24, style: .outlined, action: {})
                    BaseIconButton(icon: "gear", size: 24, style: .plain, action: {})
                }
            }
        }
        .padding()
    }
    .background(Color.appBackground)
}
