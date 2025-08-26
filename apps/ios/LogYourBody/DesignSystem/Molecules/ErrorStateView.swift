//
// ErrorStateView.swift
// LogYourBody
//
import SwiftUI

// MARK: - Error State View Molecule

struct ErrorStateView: View {
    let icon: String
    let title: String
    let message: String?
    let buttonTitle: String
    let buttonAction: () -> Void
    
    init(
        icon: String = "exclamationmark.triangle",
        title: String,
        message: String? = nil,
        buttonTitle: String = "Try Again",
        buttonAction: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.appTextSecondary)
            
            // Title
            Text(title)
                .font(.headline)
                .foregroundColor(.appText)
            
            // Message (if provided)
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Action Button
            DSButton(
                title: buttonTitle,
                style: .primary,
                size: .medium,
                action: buttonAction
            )
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        ErrorStateView(
            title: "Unable to load document",
            buttonAction: {
                // Retry action
            }
        )
        
        ErrorStateView(
            icon: "wifi.slash",
            title: "No Internet Connection",
            message: "Please check your connection and try again.",
            buttonTitle: "Retry",
            buttonAction: {
                // Retry action
            }
        )
    }
    .padding()
    .background(Color.appBackground)
}
