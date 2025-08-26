//
// DeveloperTapHandler.swift
// LogYourBody
//
import SwiftUI

// MARK: - Developer Tap Handler Molecule

struct DeveloperTapHandler<Content: View>: View {
    let onUnlock: () -> Void
    @ViewBuilder let content: (Int) -> Content
    
    @State private var tapCount = 0
    
    var body: some View {
        Button(action: handleTap) {
            content(tapCount)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleTap() {
        tapCount += 1
        if tapCount >= 7 {
            onUnlock()
            tapCount = 0
        }
        
        // Reset tap count after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if tapCount < 7 {
                tapCount = 0
            }
        }
    }
}

// MARK: - Developer Tap Indicator Atom

struct DeveloperTapIndicator: View {
    let remainingTaps: Int
    
    var body: some View {
        Text("\(remainingTaps)")
            .font(.caption2)
            .foregroundColor(.appTextTertiary)
            .transition(.opacity)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        DeveloperTapHandler(
            onUnlock: { /* Developer mode unlocked */ },
            content: { tapCount in
                HStack {
                    Text("Version 1.0.0")
                    if tapCount > 0 {
                        Spacer()
                        DeveloperTapIndicator(remainingTaps: 7 - tapCount)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        )
        
        Text("Tap 7 times to unlock developer mode")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color.appBackground)
}
