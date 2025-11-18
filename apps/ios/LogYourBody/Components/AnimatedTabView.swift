//
// AnimatedTabView.swift
// LogYourBody
//
import SwiftUI

struct AnimatedTabView: View {
    @Binding var selectedTab: Tab
    @Namespace private var namespace
    @State private var bounceAnimation = false

    enum Tab: Int, CaseIterable {
        case dashboard = 0
        case log = 1

        var icon: String {
            switch self {
            case .dashboard: return "house"
            case .log: return "plus"
            }
        }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .log: return "Log"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .dashboard: return "Dashboard tab"
            case .log: return "Add new entry"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: namespace
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                        // HapticManager.shared.buttonTap()
                        bounceAnimation.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Liquid Glass effect - matches LiquidGlassCard design
            ZStack {
                // Base glass layer with material blur
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Subtle top highlight
                VStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 4)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        )
        .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
    }
}

struct TabButton: View {
    let tab: AnimatedTabView.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Selection indicator with glass morphing effect
                    if isSelected {
                        ZStack {
                            // Base selection circle
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 44, height: 44)
                                .blur(radius: 8)

                            // Inner glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.0)
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 22
                                    )
                                )
                                .frame(width: 40, height: 40)
                        }
                        .matchedGeometryEffect(id: "selection", in: namespace)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 24, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.5))
                        .symbolEffect(.bounce, value: isSelected)
                        .scaleEffect(isSelected ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
                }
                .frame(width: 44, height: 44) // Minimum tap target
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button styling
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Animated Card Transitions
struct AnimatedCard<Content: View>: View {
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .matchedGeometryEffect(id: id, in: namespace)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 1.1).combined(with: .opacity)
            ))
    }
}

// MARK: - Animated Progress Ring
struct AnimatedProgressRing: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.appBorder, lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.appPrimary,
                            Color.appPrimary.opacity(0.8)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: animatedProgress)
        }
        .onAppear {
            animatedProgress = progress
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
    }
}

// MARK: - Smooth State Change Container
struct SmoothStateContainer<Content: View>: View {
    @Namespace private var namespace
    let id: AnyHashable
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .matchedGeometryEffect(id: id, in: namespace)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: id)
    }
}
