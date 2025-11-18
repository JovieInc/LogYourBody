//
// SkeletonLoaders.swift
// LogYourBody
//
import SwiftUI

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    let animation = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 400 - 200)
                .mask(content)
            )
            .onAppear {
                withAnimation(animation) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Progress Photo Skeleton

struct ProgressPhotoSkeleton: View {
    var body: some View {
        ZStack {
            // Fixed aspect ratio container matching actual photo
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shimmer()

            // Placeholder icon
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.1))
        }
    }
}

// MARK: - Timeline Slider Skeleton

struct TimelineSliderSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            // Date range text placeholder
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 16)
                    .shimmer()

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 16)
                    .shimmer()
            }
            .padding(.bottom, 12)

            // Slider track
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)

                // Thumb
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .offset(x: 50)
            }
            .shimmer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color.appCard.opacity(0.5))
    }
}

// MARK: - Core Metrics Row Skeleton

struct CoreMetricsRowSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            // Weight metric skeleton
            metricCardSkeleton(
                icon: "scalemass",
                title: "Weight"
            )

            // Body fat metric skeleton
            metricCardSkeleton(
                icon: "percent",
                title: "Body Fat"
            )
        }
        .padding(.horizontal, 20)
    }

    private func metricCardSkeleton(icon: String, title: String) -> some View {
        VStack(spacing: 0) {
            // Value placeholder
            HStack(alignment: .bottom, spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 36)
                    .shimmer()

                Text("lbs")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
                .frame(height: 8)

            // Title and icon
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))

                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
                .frame(height: 8)

            // Trend placeholder
            HStack(spacing: 4) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 12)
                    .shimmer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 120) // Fixed height to prevent shift
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Secondary Metrics Row Skeleton

struct SecondaryMetricsRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Steps gauge skeleton
            gaugeSkeleton(
                icon: "figure.walk",
                label: "Steps",
                size: CGSize(width: 100, height: 100)
            )

            // Compact metrics
            VStack(spacing: 12) {
                compactMetricSkeleton(icon: "ruler", label: "BMI")
                compactMetricSkeleton(icon: "figure.stand", label: "Muscle")
            }

            VStack(spacing: 12) {
                compactMetricSkeleton(icon: "drop.fill", label: "Water")
                compactMetricSkeleton(icon: "bone", label: "Bone")
            }
        }
        .padding(.horizontal, 20)
    }

    private func gaugeSkeleton(icon: String, label: String, size: CGSize) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    .frame(width: size.width, height: size.height)

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 50, height: 24)
                        .shimmer()

                    Text(label)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .frame(width: size.width, height: size.height + 24)
    }

    private func compactMetricSkeleton(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.2))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 14)
                    .shimmer()

                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 44) // Fixed height
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Full Dashboard Skeleton

struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            // Progress photo skeleton
            ProgressPhotoSkeleton()
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)

            // Fixed height bottom content
            VStack(spacing: 16) {
                // Timeline slider skeleton (only show if would have data)
                TimelineSliderSkeleton()

                // Core metrics row
                CoreMetricsRowSkeleton()

                // Secondary metrics row
                SecondaryMetricsRowSkeleton()

                // Bottom padding for tab bar
                Color.clear.frame(height: 90)
            }
        }
    }
}
