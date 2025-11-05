//
// OnboardingComponents.swift
// LogYourBody
//
import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        Color.appBackground
            .ignoresSafeArea()
    }
}

// MARK: - Onboarding Header
struct OnboardingHeader: View {
    let onBack: (() -> Void)?
    
    var body: some View {
        HStack {
            if let onBack = onBack {
                Button(
            action: {
                    onBack()
                    // HapticManager.shared.buttonTap()
                },
            label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
        )
                .modifier(LiquidGlassButtonModifier())
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

// MARK: - Onboarding Title
struct OnboardingTitle: View {
    let title: String
    let subtitle: String?
    @State private var animate = false
    
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.appText)
                .multilineTextAlignment(.center)
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animate)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .opacity(animate ? 1 : 0)
                    .offset(y: animate ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: animate)
            }
        }
        .padding(.horizontal, 24)
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Onboarding Continue Button
struct OnboardingContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    let footnote: String?
    
    init(title: String = "Continue →", isEnabled: Bool = true, footnote: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.footnote = footnote
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Button(
            action: {
                action()
                // HapticManager.shared.buttonTap()
            },
            label: {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundColor(isEnabled ? .white : .appTextTertiary)
            }
        )
            .modifier(LiquidGlassContinueButtonModifier(isEnabled: isEnabled))
            .disabled(!isEnabled)
            
            if let footnote = footnote {
                Text(footnote)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.appTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 50)
    }
}

// MARK: - Onboarding Icon
struct OnboardingIcon: View {
    let systemName: String
    let size: CGFloat
    @State private var animate = false
    
    init(systemName: String, size: CGFloat = 60) {
        self.systemName = systemName
        self.size = size
    }
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(.white.opacity(0.9))
            .opacity(animate ? 1 : 0)
            .scaleEffect(animate ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animate)
            .onAppear {
                animate = true
            }
    }
}

// MARK: - Liquid Glass Modifiers
struct OnboardingLiquidGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct LiquidGlassContinueButtonModifier: ViewModifier {
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(isEnabled ? Color.appPrimary : Color.appBorder)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(.ultraThinMaterial.opacity(isEnabled ? 0.2 : 0.1))
                        )
                )
        } else {
            content
                .background(isEnabled ? Color.appPrimary : Color.appBorder)
                .cornerRadius(28)
        }
    }
}

struct LiquidGlassFieldModifier: ViewModifier {
    let isFocused: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill((isFocused ? Color.appPrimary : Color.gray).opacity(isFocused ? 0.1 : 0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isFocused ? Color.appPrimary.opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                )
        } else {
            content
                .background(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? Color.appPrimary : Color.appBorder, lineWidth: 1)
                )
                .cornerRadius(16)
        }
    }
}

struct OnboardingLiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.appPrimary.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appPrimary.opacity(0.2), lineWidth: 1)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Onboarding Container
struct OnboardingContainer<Content: View>: View {
    let content: Content
    let showBack: Bool
    let onBack: (() -> Void)?
    
    init(showBack: Bool = true, onBack: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.showBack = showBack
        self.onBack = onBack
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(spacing: 0) {
                if showBack {
                    OnboardingHeader(onBack: onBack)
                }
                
                content
            }
        }
    }
}

// MARK: - Animated Appearance Modifier
struct AnimatedAppearance: ViewModifier {
    @State private var isVisible = false
    let delay: Double
    
    init(delay: Double = 0) {
        self.delay = delay
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    func animatedAppearance(delay: Double = 0) -> some View {
        modifier(AnimatedAppearance(delay: delay))
    }
}
