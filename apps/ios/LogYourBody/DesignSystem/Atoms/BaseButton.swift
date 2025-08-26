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
    var icon: String? = nil
    var iconPosition: IconPosition = .leading
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
            case .primary: return .appPrimary
            case .secondary: return .appPrimary.opacity(0.1)
            case .tertiary: return .appCard
            case .destructive: return .red
            case .ghost: return .clear
            case .social: return .white
            case .custom(let bg, _): return bg
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .appPrimary
            case .tertiary: return .appText
            case .destructive: return .white
            case .ghost: return .appPrimary
            case .social: return .black
            case .custom(_, let fg): return fg
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .secondary: return .appPrimary.opacity(0.5)
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
            case .small: return 36
            case .medium: return 48
            case .large: return 56
            case .custom(let height, _, _): return height
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .medium: return EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
            case .large: return EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
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

// MARK: - BaseButton

struct BaseButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnvironmentEnabled
    
    let configuration: ButtonConfiguration
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    
    @State private var isPressed = false
    
    private var isEnabled: Bool {
        configuration.isEnabled && !configuration.isLoading && isEnvironmentEnabled
    }
    
    var body: some View {
        Button(action: handleTap) {
            buttonContent
                .frame(maxWidth: configuration.fullWidth ? .infinity : nil)
                .frame(height: configuration.size.height)
                .padding(configuration.size.padding)
                .background(backgroundView)
                .cornerRadius(10)
                .overlay(borderOverlay)
                .scaleEffect(isPressed || configuration.isLoading ? 0.98 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
                .animation(.easeInOut(duration: 0.15), value: configuration.isLoading)
        }
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
    
    @ViewBuilder
    private var buttonContent: some View {
        if configuration.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: configuration.style.foregroundColor))
                .scaleEffect(0.8)
        } else {
            label()
                .font(.system(size: configuration.size.fontSize, weight: .semibold))
                .foregroundColor(configuration.style.foregroundColor)
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        configuration.style.backgroundColor
    }
    
    @ViewBuilder
    private var borderOverlay: some View {
        if let borderColor = configuration.style.borderColor {
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1.5)
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

extension BaseButton where Label == HStack<TupleView<(ConditionalContent<Image, EmptyView>, Text, ConditionalContent<Image, EmptyView>)>> {
    init(
        _ title: String,
        configuration: ButtonConfiguration = ButtonConfiguration(),
        action: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.action = action
        self.label = {
            HStack(spacing: 8) {
                if configuration.iconPosition == .leading, let icon = configuration.icon {
                    Image(systemName: icon)
                        .font(.system(size: configuration.size.iconSize))
                } else {
                    EmptyView()
                }
                
                Text(title)
                
                if configuration.iconPosition == .trailing, let icon = configuration.icon {
                    Image(systemName: icon)
                        .font(.system(size: configuration.size.iconSize))
                } else {
                    EmptyView()
                }
            }
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
        }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.appText)
                .frame(width: size * 2, height: size * 2)
                .background(
                    Circle()
                        .fill(style.backgroundColor)
                        .overlay(
                            style.borderColor.map { color in
                                Circle().stroke(color, lineWidth: 1)
                            }
                        )
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
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
            
            Divider()
            
            // Custom content
            Group {
                Text("Custom Content").font(.headline)
                BaseButton(configuration: ButtonConfiguration(), action: {}) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Sign in with Apple")
                    }
                }
            }
        }
        .padding()
    }
    .background(Color.appBackground)
}