//
// LiquidGlassTimelineSlider.swift
// LogYourBody
//
import SwiftUI

struct LiquidGlassTimelineSlider: View {
    @Binding var selectedIndex: Int
    let metrics: [BodyMetrics]
    let ticks: [TimelineTick]
    let onChange: (Int) -> Void
    let onJumpToNext: () -> Void
    let onJumpToPrevious: () -> Void
    
    @State private var isDragging = false
    @State private var thumbScale: CGFloat = 1.0
    @State private var liquidPhase: CGFloat = 0
    @State private var rippleAmplitude: CGFloat = 0
    @State private var glassDistortion: CGFloat = 0
    @State private var currentVelocity: CGFloat = 0
    @State private var magneticPull: CGFloat = 0
    
    private var progress: Double {
        guard metrics.count > 1 else { return 0 }
        return Double(selectedIndex) / Double(metrics.count - 1)
    }
    
    private var photoMetrics: [BodyMetrics] {
        metrics.filter { $0.photoUrl != nil }
    }
    
    private var hasPhotos: Bool {
        !photoMetrics.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Photo navigation with glass effect
            if hasPhotos {
                HStack(spacing: 20) {
                    // Previous photo button
                    GlassNavigationButton(
                        icon: "chevron.left",
                        secondaryIcon: "photo.fill",
                        action: onJumpToPrevious
                    )
                    
                    Spacer()
                    
                    // Photo indicator with glass badge
                    ZStack {
                        // Glass background
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                        
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.appPrimary)
                            
                            Text("\(getCurrentPhotoPosition())/\(photoMetrics.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .fixedSize()
                    
                    Spacer()
                    
                    // Next photo button
                    GlassNavigationButton(
                        icon: "chevron.right",
                        secondaryIcon: "photo.fill",
                        isLeading: false,
                        action: onJumpToNext
                    )
                }
            }
            
            // Liquid Glass Timeline
            GeometryReader { geometry in
                ZStack(alignment: .center) {
                    // Liquid glass background
                    LiquidGlassTrack(
                        progress: progress,
                        isDragging: isDragging,
                        liquidPhase: liquidPhase,
                        rippleAmplitude: rippleAmplitude,
                        glassDistortion: glassDistortion
                    )
                    
                    // Photo thumbnails with glass effect
                    ForEach(ticks.filter({ $0.isPhotoAnchor }), id: \.index) { tick in
                        let tickProgress = Double(tick.index) / Double(metrics.count - 1)
                        let xPosition = geometry.size.width * CGFloat(tickProgress)
                        
                        if let photoUrl = tick.photoUrl {
                            LiquidPhotoAnchor(
                                photoUrl: photoUrl,
                                isSelected: tick.index == selectedIndex,
                                magneticPull: calculateMagneticPull(for: tick.index)
                            )
                            .position(x: xPosition, y: 20)
                            .zIndex(tick.index == selectedIndex ? 2 : 1)
                        }
                    }
                    
                    // Liquid glass thumb
                    LiquidGlassThumb(
                        scale: thumbScale,
                        isDragging: isDragging,
                        velocity: currentVelocity
                    )
                    .position(
                        x: geometry.size.width * CGFloat(progress),
                        y: 20
                    )
                    .zIndex(3)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value, in: geometry)
                        }
                        .onEnded { value in
                            handleDragEnded(value, in: geometry)
                        }
                )
            }
            .frame(height: 40)
        }
        .onAppear {
            startLiquidAnimation()
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleDragChanged(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        if !isDragging {
            isDragging = true
            thumbScale = 1.15
            
            // Start glass distortion
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                glassDistortion = 1.0
            }
            
            HapticManager.shared.buttonTapped()
        }
        
        // Calculate velocity for liquid effect
        currentVelocity = value.velocity.width / 1_000
        
        // Update position with magnetic anchoring
        let rawProgress = value.location.x / geometry.size.width
        let newIndex = calculateMagneticIndex(for: rawProgress)
        
        if newIndex != selectedIndex {
            selectedIndex = newIndex
            onChange(newIndex)
            
            // Enhanced haptics for photo anchors
            if ticks.first(where: { $0.index == newIndex })?.isPhotoAnchor == true {
                // Trigger ripple effect
                triggerRipple()
                HapticManager.shared.toggleChanged()
            } else {
                HapticManager.shared.sliderChanged()
            }
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        isDragging = false
        currentVelocity = 0
        
        // Animate back to rest state
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            thumbScale = 1.0
            glassDistortion = 0
        }
        
        // Add momentum snap to nearest photo
        let velocity = value.predictedEndLocation.x - value.location.x
        snapToNearestPhoto(with: velocity, in: geometry)
        
        HapticManager.shared.sliderEnded()
    }
    
    // MARK: - Helper Methods
    
    private func startLiquidAnimation() {
        // Continuous liquid phase animation
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            liquidPhase = .pi * 2
        }
    }
    
    private func triggerRipple() {
        rippleAmplitude = 8
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
            rippleAmplitude = 0
        }
    }
    
    private func calculateMagneticIndex(for progress: CGFloat) -> Int {
        let targetIndex = Int(round(progress * Double(metrics.count - 1)))
        
        // Find nearby photo anchors
        let magneticRange = 5 // indices
        let nearbyPhotos = ticks.filter { tick in
            tick.isPhotoAnchor &&
            abs(tick.index - targetIndex) <= magneticRange
        }
        
        // Apply magnetic effect to closest photo
        if let closestPhoto = nearbyPhotos.min(by: {
            abs($0.index - targetIndex) < abs($1.index - targetIndex)
        }) {
            let distance = abs(closestPhoto.index - targetIndex)
            let magneticStrength = 1.0 - (Double(distance) / Double(magneticRange))
            
            // Only snap if within magnetic threshold
            if magneticStrength > 0.3 {
                return closestPhoto.index
            }
        }
        
        return targetIndex
    }
    
    private func calculateMagneticPull(for index: Int) -> CGFloat {
        let distance = abs(index - selectedIndex)
        let maxDistance: CGFloat = 5
        
        if distance == 0 {
            return isDragging ? 1.0 : 0.8
        } else if CGFloat(distance) < maxDistance {
            return (1.0 - CGFloat(distance) / maxDistance) * 0.3
        }
        return 0
    }
    
    private func snapToNearestPhoto(with velocity: CGFloat, in geometry: GeometryProxy) {
        // Find photo in direction of velocity
        let currentProgress = Double(selectedIndex) / Double(metrics.count - 1)
        let searchDirection = velocity > 0 ? 1 : -1
        
        let nearbyPhotos = ticks.filter { tick in
            tick.isPhotoAnchor &&
            ((searchDirection > 0 && tick.index > selectedIndex) ||
             (searchDirection < 0 && tick.index < selectedIndex))
        }
        
        if let targetPhoto = nearbyPhotos.first {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedIndex = targetPhoto.index
                onChange(targetPhoto.index)
            }
        }
    }
    
    private func getCurrentPhotoPosition() -> Int {
        guard selectedIndex < metrics.count,
              let photoIndex = photoMetrics.firstIndex(where: { $0.id == metrics[selectedIndex].id }) else {
            return 1
        }
        return photoIndex + 1
    }
}

// MARK: - Liquid Glass Track

struct LiquidGlassTrack: View {
    let progress: Double
    let isDragging: Bool
    let liquidPhase: CGFloat
    let rippleAmplitude: CGFloat
    let glassDistortion: CGFloat
    
    var body: some View {
        ZStack {
            // Base glass layer
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.03))
                )
            
            // Liquid wave overlay
            Canvas { context, size in
                let path = createLiquidPath(in: size)
                
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: 0)
                    )
                )
            }
            
            // Progress fill with glass effect
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.15)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(40, geometry.size.width * progress))
                    .blur(radius: isDragging ? 2 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
            }
            
            // Glass border
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        }
        .frame(height: 40)
        .scaleEffect(y: 1 + glassDistortion * 0.1)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: glassDistortion)
    }
    
    private func createLiquidPath(in size: CGSize) -> Path {
        var path = Path()
        let waveHeight = rippleAmplitude
        let progressPoint = size.width * progress
        
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        
        // Create liquid wave around progress point
        for x in stride(from: 0, through: size.width, by: 1) {
            let relativeX = x - progressPoint
            let waveOffset = sin(relativeX * 0.02 + liquidPhase) * waveHeight
            let dampening = exp(-pow(relativeX / 100, 2))
            let y = size.height / 2 + waveOffset * dampening
            
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Liquid Glass Thumb

struct LiquidGlassThumb: View {
    let scale: CGFloat
    let isDragging: Bool
    let velocity: CGFloat
    
    @State private var glowAnimation = false
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 40, height: 40)
                .blur(radius: isDragging ? 6 : 3)
                .scaleEffect(glowAnimation ? 1.2 : 1.0)
            
            // Glass sphere
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .frame(width: 24, height: 24)
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(velocity * 30),
                    axis: (x: 0, y: 1, z: 0)
                )
            
            // Inner light
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 8, height: 8)
                .offset(x: -4, y: -4)
                .blur(radius: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever()) {
                glowAnimation = true
            }
        }
    }
}

// MARK: - Liquid Photo Anchor

struct LiquidPhotoAnchor: View {
    let photoUrl: String
    let isSelected: Bool
    let magneticPull: CGFloat
    
    @State private var imageLoaded = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Magnetic field visualization
            if magneticPull > 0 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.appPrimary.opacity(0.3 * magneticPull),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
                    .blur(radius: 4)
            }
            
            // Glass container
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    AsyncImage(url: URL(string: photoUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                            .onAppear { imageLoaded = true }
                    } placeholder: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 24, height: 24)
                    }
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.appPrimary : Color.white.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                )
                .frame(width: 28, height: 28)
                .scaleEffect(isSelected ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .onAppear {
            if isSelected {
                withAnimation(.easeInOut(duration: 1.5).repeatForever()) {
                    pulseAnimation = true
                }
            }
        }
    }
}

// MARK: - Glass Navigation Button

struct GlassNavigationButton: View {
    let icon: String
    let secondaryIcon: String
    var isLeading: Bool = true
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLeading {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: secondaryIcon)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Image(systemName: secondaryIcon)
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(isPressed ? 0.1 : 0.05))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
