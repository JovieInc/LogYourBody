//
// LiquidGlassTabBar.swift
// LogYourBody
//
// Organism: Liquid Glass Tab Bar
// A complex navigation component with liquid animation effects
//
import SwiftUI

struct LiquidGlassTabBar: View {
    @Binding var selectedTab: AnimatedTabView.Tab
    @Namespace private var namespace
    @State private var selectedRect: CGRect = .zero
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var springVelocity: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(AnimatedTabView.Tab.allCases, id: \.self) { tab in
                    LiquidTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        namespace: namespace,
                        containerGeometry: geometry
                    ) { rect in
                        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
                            selectedTab = tab
                            selectedRect = rect
                            HapticManager.shared.buttonTapped()
                        }
                    }
                }
            }
            .background(
                // Animated liquid background
                LiquidGlassBackground(
                    selectedRect: selectedRect,
                    isDragging: isDragging,
                    dragOffset: dragOffset,
                    namespace: namespace
                )
            )
        }
        .frame(height: 56)
        .padding(.horizontal, 8)
        .background(
            // Main glass container
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .scaleEffect(isDragging ? 0.98 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDragging)
    }
}

// MARK: - Molecules

struct LiquidTabButton: View {
    let tab: AnimatedTabView.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let containerGeometry: GeometryProxy
    let onTap: (CGRect) -> Void
    
    @State private var isPressed = false
    @State private var buttonRect: CGRect = .zero
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            Button(
                action: {
                    // Get button position for liquid animation
                    let frame = geometry.frame(in: .named("tabBar"))
                    onTap(frame)
                    
                    // Trigger ripple effect
                    withAnimation(.easeOut(duration: 0.6)) {
                        rippleScale = 2
                        rippleOpacity = 0
                    }
                    
                    // Reset ripple
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        rippleScale = 0
                        rippleOpacity = 0.3
                    }
                }, label: {
                VStack(spacing: 4) {
                    ZStack {
                        // Ripple effect
                        Circle()
                            .fill(Color.white.opacity(rippleOpacity))
                            .scaleEffect(rippleScale)
                            .frame(width: 40, height: 40)
                            .allowsHitTesting(false)
                        
                        // Icon with liquid animation
                        DSIcon(
                            systemName: tab.icon,
                            size: 24,
                            weight: isSelected ? .medium : .regular,
                            color: isSelected ? .white : Color.white.opacity(0.5)
                        )
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .rotationEffect(.degrees(isSelected ? 360 : 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isSelected)
                    }
                    .frame(width: 44, height: 44)
                }
                .frame(maxWidth: .infinity)
                .scaleEffect(isPressed ? 0.85 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            })
            .buttonStyle(PlainButtonStyle())
            .coordinateSpace(name: "tabBar")
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
        }
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct LiquidGlassBackground: View {
    let selectedRect: CGRect
    let isDragging: Bool
    let dragOffset: CGFloat
    let namespace: Namespace.ID
    
    @State private var phase: CGFloat = 0
    @State private var waveAmplitude: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            // Create liquid glass path
            let path = createLiquidPath(in: size)
            
            // Main glass fill
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05)
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )
            
            // Animated highlight
            let highlightPath = createHighlightPath(in: size)
            context.fill(
                highlightPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.2),
                        Color.clear
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: selectedRect)
        .onAppear {
            // Start wave animation
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onChange(of: selectedRect) { _, _ in
            // Trigger wave on selection change
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                waveAmplitude = 5
            }
            
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3)) {
                waveAmplitude = 0
            }
        }
    }
    
    private func createLiquidPath(in size: CGSize) -> Path {
        var path = Path()
        
        let minX = selectedRect.minX
        let maxX = selectedRect.maxX
        let midX = selectedRect.midX
        let width = selectedRect.width
        
        // Start from left
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: 20))
        
        // Liquid curve to selection
        if selectedRect != .zero {
            // Left approach curve
            path.addCurve(
                to: CGPoint(x: minX - 10, y: 10),
                control1: CGPoint(x: minX - 30, y: 20),
                control2: CGPoint(x: minX - 20, y: 15)
            )
            
            // Selection bubble with wave
            let waveOffset = sin(phase) * waveAmplitude
            path.addQuadCurve(
                to: CGPoint(x: midX, y: 5 + waveOffset),
                control: CGPoint(x: minX + width * 0.25, y: 0)
            )
            
            path.addQuadCurve(
                to: CGPoint(x: maxX + 10, y: 10),
                control: CGPoint(x: maxX - width * 0.25, y: 0)
            )
            
            // Right departure curve
            path.addCurve(
                to: CGPoint(x: size.width, y: 20),
                control1: CGPoint(x: maxX + 20, y: 15),
                control2: CGPoint(x: maxX + 30, y: 20)
            )
        } else {
            // Flat line when no selection
            path.addLine(to: CGPoint(x: size.width, y: 20))
        }
        
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        
        return path
    }
    
    private func createHighlightPath(in size: CGSize) -> Path {
        var path = Path()
        
        if selectedRect != .zero {
            let center = CGPoint(x: selectedRect.midX, y: 15)
            let radius = selectedRect.width * 0.6
            
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius * 0.5,
                width: radius * 2,
                height: radius
            ))
        }
        
        return path
    }
}

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @State private var selectedTab = AnimatedTabView.Tab.dashboard
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    LiquidGlassTabBar(selectedTab: $selectedTab)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    return PreviewContainer()
}
