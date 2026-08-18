//
// AnimatedTabView.swift
// LogYourBody
//
import SwiftUI

struct AnimatedTabView: View {
    @Binding var selectedTab: Tab
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
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                        bounceAnimation.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .dashboardChromeGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            cornerRadius: 24
        )
    }
}

struct TabButton: View {
    let tab: AnimatedTabView.Tab
    let isSelected: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 24, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.5))
                    .symbolEffect(.bounce, value: isSelected)
                    .scaleEffect(isSelected ? 1.0 : 0.9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
                    .frame(width: 44, height: 44)
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
