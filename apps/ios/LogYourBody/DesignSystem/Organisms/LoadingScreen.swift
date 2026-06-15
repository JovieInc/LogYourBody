//
// LoadingScreen.swift
// LogYourBody
//
import SwiftUI

// MARK: - LoadingScreen Organism

/// A full-screen loading view with logo, progress bar, and status text
struct LoadingScreen: View {
    @Binding var progress: Double
    @Binding var loadingStatus: String
    let onComplete: () -> Void
    @State private var didScheduleCompletion = false

    var backgroundColor = Color("LaunchScreenBackground")
    var showPercentage: Bool = true
    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Animated Logo
                DSLogoAnimated(
                    size: 80,
                    color: .white,
                    textSize: 28,
                    animationDuration: 0.6
                )

                Spacer()

                // Progress section
                VStack(spacing: 16) {
                    // Status text
                    DSText(
                        loadingStatus,
                        style: .footnote,
                        color: .white.opacity(0.7)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 20)

                    // Progress bar
                    DSProgressBar(
                        progress: clampedProgress,
                        height: 8,
                        backgroundColor: .white.opacity(0.2),
                        foregroundColor: .white,
                        animationDuration: 0.4
                    )
                    .padding(.horizontal, 60)

                    // Percentage
                    if showPercentage {
                        DSText(
                            "\(Int(clampedProgress * 100))%",
                            style: .caption,
                            weight: .medium,
                            color: .white.opacity(0.5)
                        )
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            checkCompletion()
        }
        .onChange(of: clampedProgress) { _ in
            checkCompletion()
        }
    }

    private func checkCompletion() {
        guard clampedProgress >= 1.0, !didScheduleCompletion else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard clampedProgress >= 1.0, !didScheduleCompletion else {
                return
            }
            didScheduleCompletion = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            onComplete()
        }
    }
}

// MARK: - CompactLoadingScreen

/// A compact loading view that can be embedded in other views
struct CompactLoadingScreen: View {
    @Binding var isLoading: Bool
    var message: String = "Loading..."
    var showProgress: Bool = false
    @Binding var progress: Double

    var body: some View {
        if isLoading {
            VStack(spacing: 16) {
                DSCircularProgress(
                    progress: showProgress ? progress : 0.75,
                    size: 50,
                    lineWidth: 3,
                    showPercentage: showProgress
                )

                DSText(
                    message,
                    style: .footnote,
                    color: .appTextSecondary
                )
            }
            .padding(24)
            .background(Color.appCard)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        // Full screen loading
        LoadingScreen(
            progress: .constant(0.6),
            loadingStatus: .constant("Loading user data..."),
            onComplete: {
                // print("Loading complete")
            }
        )
    }
}

#Preview("Compact Loading") {
    ZStack {
        Color.appBackground
            .ignoresSafeArea()

        VStack(spacing: 30) {
            // Simple loading
            CompactLoadingScreen(
                isLoading: .constant(true),
                message: "Please wait...",
                showProgress: false,
                progress: .constant(0)
            )

            // With progress
            CompactLoadingScreen(
                isLoading: .constant(true),
                message: "Uploading photos...",
                showProgress: true,
                progress: .constant(0.75)
            )
        }
    }
}
