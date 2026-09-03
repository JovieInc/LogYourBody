//
// LoadingScreen.swift
// LogYourBody
//
import SwiftUI

// MARK: - LoadingScreen Organism

/// Splash B (splash-b-everywhere-v1): a tiny centered cream mark on an empty
/// night field. No type, no hero, no wordmark. Progress is a 2pt hairline the
/// width of the mark so launch still reads as returning to data.
enum SplashBGeometry {
    static let markSize: CGFloat = 32
    static let progressHeight: CGFloat = 2
    static let progressWidth: CGFloat = markSize
}

struct LoadingScreen: View {
    @Binding var progress: Double
    @Binding var loadingStatus: String
    let onComplete: () -> Void
    @State private var didScheduleCompletion = false

    var backgroundColor = Color("LaunchScreenBackground")
    var showPercentage: Bool = false
    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: JovieTokens.tightGap) {
                Image("LaunchLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: SplashBGeometry.markSize, height: SplashBGeometry.markSize)
                    .foregroundStyle(Color.jovieCream)
                    .accessibilityHidden(true)

                DSProgressBar(
                    progress: clampedProgress,
                    height: SplashBGeometry.progressHeight,
                    backgroundColor: .jovieHairline,
                    foregroundColor: .jovieCream,
                    animationDuration: JovieTokens.cinematicDuration
                )
                .frame(width: SplashBGeometry.progressWidth)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading your latest data")
            .accessibilityValue(loadingStatus.isEmpty ? "Your last view is ready first. Sync continues quietly." : loadingStatus)
        }
        .onAppear {
            checkCompletion()
        }
        .onChange(of: clampedProgress) { _, _ in
            checkCompletion()
        }
        .worldClassScreen(.launch)
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
            VStack(spacing: JovieTokens.itemGap) {
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
            .padding(JovieTokens.compactInset)
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
