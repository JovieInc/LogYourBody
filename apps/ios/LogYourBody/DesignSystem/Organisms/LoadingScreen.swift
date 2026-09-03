//
// LoadingScreen.swift
// LogYourBody
//
import SwiftUI

// MARK: - LoadingScreen Organism

/// A quiet continuity surface. Launch should feel like returning to data, not
/// waiting through branded progress theatre.
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

            VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                Spacer()

                Text("Loading your latest data")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.jovieText)

                Text(loadingStatus.isEmpty ? "Your last view is ready first. Sync continues quietly." : loadingStatus)
                    .font(.body)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                DSProgressBar(
                    progress: clampedProgress,
                    height: 2,
                    backgroundColor: .jovieHairline,
                    foregroundColor: .jovieText,
                    animationDuration: JovieTokens.cinematicDuration
                )
                .padding(.top, 8)

                if showPercentage {
                    Text("\(Int(clampedProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.jovieTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.vertical, 64)
            .frame(maxWidth: 440, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading your latest data")
            .accessibilityValue(loadingStatus)
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

        VStack(spacing: 32) {
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
