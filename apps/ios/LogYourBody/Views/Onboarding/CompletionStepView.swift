//
// CompletionStepView.swift
// LogYourBody
//
import SwiftUI
import UIKit


struct CompletionStepView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @EnvironmentObject var authManager: AuthManager
    @State private var animateCheckmark = false
    @State private var animateContent = false

    // Computed properties for cleaner code
    private var hasProfileData: Bool {
        !viewModel.data.name.isEmpty ||
            viewModel.data.dateOfBirth != nil ||
            viewModel.data.totalHeightInInches > 0 ||
            viewModel.data.gender != nil
    }

    var body: some View {
        ZStack {
            // Edge-to-edge background
            Color.appBackground
                .ignoresSafeArea()

            // Custom floating header
            HStack {
                Button(
                    action: {
                        viewModel.previousStep()
                        HapticManager.shared.buttonTap()
                    },
                    label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.appTextSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                Spacer()
            }
            .padding(.top, 44)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 24) {
                // Subtitle
                Text("Just a moment while we set everything up…")
                    .font(.system(size: 16))
                    .foregroundColor(.appText.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Constants.paddingLarge)

                // Steps checklist in a glass card
                GlassCard {
                    VStack(spacing: 20) {
                        ModernDataRow(icon: "checkmark.circle.fill", iconColor: .appPrimary, label: "Creating your profile", value: "")
                        ModernDataRow(icon: "checkmark.circle.fill", iconColor: .appPrimary, label: "Setting up your dashboard", value: "")
                        ModernDataRow(icon: "checkmark.circle.fill", iconColor: .appPrimary, label: "Configuring health sync", value: "")
                    }
                    .padding(24)
                }
                .padding(.horizontal, Constants.paddingLarge)

                Spacer()

                // Primary CTA
                LiquidGlassCTAButton(
                    text: "Go to Dashboard",
                    icon: "arrow.right",
                    action: {
                        Task {
                            await viewModel.completeOnboarding(authManager: authManager)
                        }
                    },
                    isEnabled: true
                )
                .padding(.horizontal, Constants.paddingLarge)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Simple staggered animations
            withAnimation {
                animateCheckmark = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                animateContent = true
            }
        }
    }
}

// MARK: - Checkmark Shape
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height

        path.move(to: CGPoint(x: width * 0.2, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.4, y: height * 0.7))
        path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.3))

        return path
    }
}

// MARK: - Modern Data Row Component
struct ModernDataRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))

            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.appTextSecondary)

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appText)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.appBackground
            .ignoresSafeArea()

        CompletionStepView()
            .environmentObject({
                let vm = OnboardingViewModel()
                vm.data.name = "John Doe"
                vm.data.dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date())
                vm.data.heightFeet = 5
                vm.data.heightInches = 10
                vm.data.gender = .male
                return vm
            }())
            .environmentObject(AuthManager())
    }
}
