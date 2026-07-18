//
// DashboardComponents.swift
// LogYourBody
//
import SwiftUI

// MARK: - Empty State View

struct DashboardEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String = "Get Started"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.appTextSecondary)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.appText)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.appPrimary)
                        .cornerRadius(24)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}
