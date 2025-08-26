//
// LoadingView.swift
// LogYourBody
//
import SwiftUI

/// Legacy loading view - use LoadingScreen from Design System instead
struct LoadingView: View {
    @Binding var progress: Double
    @Binding var loadingStatus: String
    let onComplete: () -> Void
    
    var body: some View {
        LoadingScreen(
            progress: $progress,
            loadingStatus: $loadingStatus,
            onComplete: onComplete
        )
    }
}

#Preview {
    LoadingView(
        progress: .constant(0.6),
        loadingStatus: .constant("Loading..."),
        onComplete: {}
    )
}
