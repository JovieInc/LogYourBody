//
// AnimatedTaskIcon.swift
// LogYourBody
//
import SwiftUI

// MARK: - Animated Task Icon Atom

/// An animated SF Symbol icon for background tasks
struct AnimatedTaskIcon: View {
    let iconName: String
    let animationType: AnimationType
    let size: CGFloat
    let color: Color

    @State private var isAnimating = false

    enum AnimationType {
        case rotate          // Continuous rotation (scanning)
        case pulse          // Scale pulse (importing/uploading)
        case bounce         // Bounce animation (processing)
        case shimmer        // Opacity shimmer (uploading)
        case none           // No animation
    }

    init(
        iconName: String,
        animationType: AnimationType = .pulse,
        size: CGFloat = 20,
        color: Color = .appPrimary
    ) {
        self.iconName = iconName
        self.animationType = animationType
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(color)
            .modifier(AnimationModifier(type: animationType, isAnimating: $isAnimating))
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        switch animationType {
        case .rotate:
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        case .pulse:
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        case .bounce:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        case .shimmer:
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        case .none:
            break
        }
    }
}

// MARK: - Animation Modifier

private struct AnimationModifier: ViewModifier {
    let type: AnimatedTaskIcon.AnimationType
    @Binding var isAnimating: Bool

    func body(content: Content) -> some View {
        switch type {
        case .rotate:
            content
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
        case .pulse:
            content
                .scaleEffect(isAnimating ? 1.15 : 1.0)
        case .bounce:
            content
                .offset(y: isAnimating ? -4 : 0)
        case .shimmer:
            content
                .opacity(isAnimating ? 0.5 : 1.0)
        case .none:
            content
        }
    }
}

// MARK: - Convenience Initializers

extension AnimatedTaskIcon {
    /// Create icon from BackgroundTaskType
    init(taskType: BackgroundTaskType, size: CGFloat = 20, color: Color = .appPrimary) {
        let animation: AnimationType = {
            switch taskType {
            case .scanning: return .rotate
            case .importing: return .pulse
            case .uploading: return .shimmer
            case .processing: return .pulse
            }
        }()

        self.init(
            iconName: taskType.iconName,
            animationType: animation,
            size: size,
            color: color
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 32) {
            VStack {
                AnimatedTaskIcon(
                    iconName: "magnifyingglass.circle.fill",
                    animationType: .rotate,
                    size: 32
                )
                Text("Rotate")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            VStack {
                AnimatedTaskIcon(
                    iconName: "arrow.down.circle.fill",
                    animationType: .pulse,
                    size: 32
                )
                Text("Pulse")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            VStack {
                AnimatedTaskIcon(
                    iconName: "sparkles",
                    animationType: .bounce,
                    size: 32
                )
                Text("Bounce")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            VStack {
                AnimatedTaskIcon(
                    iconName: "icloud.and.arrow.up",
                    animationType: .shimmer,
                    size: 32
                )
                Text("Shimmer")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }

        Divider()

        // Task type examples
        VStack(spacing: 16) {
            Text("Task Types")
                .font(.headline)
                .foregroundColor(.appText)

            HStack(spacing: 24) {
                AnimatedTaskIcon(taskType: .scanning, size: 28)
                AnimatedTaskIcon(taskType: .importing, size: 28)
                AnimatedTaskIcon(taskType: .uploading, size: 28)
                AnimatedTaskIcon(taskType: .processing, size: 28)
            }
        }
    }
    .padding()
    .background(Color.appBackground)
}
