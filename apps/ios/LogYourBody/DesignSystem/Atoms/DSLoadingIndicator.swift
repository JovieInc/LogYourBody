//
// LoadingIndicator.swift
// LogYourBody
//
import SwiftUI

// MARK: - Loading Indicator Atom

struct LoadingIndicator: View {
    let message: String
    let scale: CGFloat
    
    init(message: String = "Loading...", scale: CGFloat = 1.2) {
        self.message = message
        self.scale = scale
    }
    
    var body: some View {
        ProgressView(message)
            .progressViewStyle(CircularProgressViewStyle(tint: .appPrimary))
            .scaleEffect(scale)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        LoadingIndicator()
        
        LoadingIndicator(message: "Fetching data...")
        
        LoadingIndicator(message: "Please wait", scale: 1.5)
    }
    .padding()
    .background(Color.appBackground)
}
