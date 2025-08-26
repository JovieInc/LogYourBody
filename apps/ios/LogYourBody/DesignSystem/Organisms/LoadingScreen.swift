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
    
    var backgroundColor: Color = Color(red: 0.071, green: 0.071, blue: 0.114)
    var showPercentage: Bool = true
    
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
                        size: .system(size: 14),
                        color: .white.opacity(0.7)
                    )
                    .frame(minHeight: 20)
                    .animation(.easeInOut(duration: 0.3), value: loadingStatus)
                    
                    // Progress bar
                    DSProgressBar(
                        progress: progress,
                        height: 8,
                        backgroundColor: .white.opacity(0.2),
                        foregroundColor: .white,
                        animationDuration: 0.4
                    )
                    .padding(.horizontal, 60)
                    
                    // Percentage
                    if showPercentage {
                        DSText(
                            "\(Int(progress * 100))%",
                            size: .system(size: 12, weight: .medium),
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
        .onChange(of: progress) { _ in
            checkCompletion()
        }
    }
    
    private func checkCompletion() {
        if progress >= 1.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
            }
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
                    size: .system(size: 14),
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
                print("Loading complete")
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