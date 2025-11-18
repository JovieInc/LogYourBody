//
// OnboardingContainerView.swift
// LogYourBody
//
import SwiftUI

struct OnboardingContainerView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var backgroundOffset: CGFloat = 0

    // Dynamic liquid glass properties based on current step
    private var liquidGlassOpacity: Double {
        switch viewModel.currentStep {
        case .welcome:
            return 0.6
        case .healthKit, .progressPhotos, .notifications:
            return 0.4
        default:
            return 0.3
        }
    }

    private var liquidGlassGradient: [Color] {
        switch viewModel.currentStep {
        case .welcome:
            return [
                Color.appPrimary.opacity(0.08),
                Color.appPrimary.opacity(0.03),
                Color.clear
            ]
        case .healthKit:
            return [
                Color.red.opacity(0.05),
                Color.appPrimary.opacity(0.02),
                Color.clear
            ]
        default:
            return [
                Color.appPrimary.opacity(0.05),
                Color.appPrimary.opacity(0.02),
                Color.clear
            ]
        }
    }

    var body: some View {
        ZStack {
            // Adaptive glass background
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: liquidGlassGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Glass overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(liquidGlassOpacity)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Modern progress indicator
                if viewModel.currentStep != .welcome && viewModel.currentStep != .profilePreparation {
                    VStack(spacing: 0) {
                        // Step dots indicator
                        HStack(spacing: 6) {
                            ForEach(OnboardingViewModel.OnboardingStep.allCases.filter { $0 != .welcome && $0 != .profilePreparation }, id: \.self) { step in
                                StepIndicator(
                                    isActive: step == viewModel.currentStep,
                                    isCompleted: step.rawValue < viewModel.currentStep.rawValue
                                )
                            }
                        }
                        .padding(.horizontal, Constants.paddingLarge)
                        .padding(.vertical, Constants.padding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Onboarding progress")
                        .accessibilityValue("Step \(viewModel.currentStep.rawValue) of \(OnboardingViewModel.OnboardingStep.allCases.filter { $0 != .welcome && $0 != .profilePreparation }.count)")

                        // Subtle separator
                        Rectangle()
                            .fill(Color.appBorder.opacity(0.2))
                            .frame(height: 1)
                    }
                    .background(Color.appBackground)
                }

                // Content with animation
                ZStack {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeStepView()
                            .environmentObject(viewModel)
                    case .name:
                        NameInputView()
                            .environmentObject(viewModel)
                    case .dateOfBirth:
                        DateOfBirthInputView()
                            .environmentObject(viewModel)
                    case .height:
                        HeightInputView()
                            .environmentObject(viewModel)
                    case .gender:
                        GenderInputView()
                            .environmentObject(viewModel)
                    case .healthKit:
                        HealthKitStepView()
                            .environmentObject(viewModel)
                    case .progressPhotos:
                        ProgressPhotosStepView()
                            .environmentObject(viewModel)
                    case .notifications:
                        NotificationsStepView()
                            .environmentObject(viewModel)
                    case .profilePreparation:
                        ProfilePreparationView(
                            onboardingData: $viewModel.data,
                            onComplete: {
                                Task {
                                    await viewModel.completeOnboarding(authManager: authManager)
                                }
                            }
                        )
                        .environmentObject(viewModel)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.smooth, value: viewModel.currentStep)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.currentStep) { _, _ in
            // Subtle haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Step Indicator Component
struct StepIndicator: View {
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        Circle()
            .fill(
                isCompleted ? Color.appPrimary :
                    isActive ? Color.appPrimary :
                    Color.appBorder
            )
            .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
            .opacity(isCompleted ? 1 : isActive ? 1 : 0.5)
            .animation(.easeOut(duration: 0.2), value: isActive)
            .animation(.easeOut(duration: 0.2), value: isCompleted)
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AuthManager())
}
