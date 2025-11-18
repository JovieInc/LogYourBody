//
// ProcessingImagePlaceholder.swift
// LogYourBody
//
import SwiftUI

struct ProcessingImagePlaceholder: View {
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appBorder, lineWidth: 1)
                )

            // Processing indicator
            VStack(spacing: 16) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0.6 : 1.0)

                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.appPrimary)
                }

                VStack(spacing: 4) {
                    Text("Processing...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appText)

                    Text("AI background removal")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

#if DEBUG
struct ProcessingImagePlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingImagePlaceholder()
            .frame(width: 300, height: 400)
            .preferredColorScheme(.dark)
    }
}
#endif
