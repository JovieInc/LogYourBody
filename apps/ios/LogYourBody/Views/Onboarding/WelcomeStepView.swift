//
// WelcomeStepView.swift
// LogYourBody
//
import SwiftUI

struct WelcomeStepView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @EnvironmentObject var authManager: AuthManager
    @State private var animate = false
    #if DEBUG
    @State private var showDebugOptions = false
    #endif

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 40) {
                    // Icon
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.9))

                    // Welcome text
                    VStack(spacing: 20) {
                        if let userName = authManager.currentUser?.displayName ?? authManager.currentUser?.name {
                            Text("Welcome, \(userName).")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .opacity(animate ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.1), value: animate)

                            Text("Review your details to begin")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .opacity(animate ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.2), value: animate)
                        } else {
                            Text("Welcome to LogYourBody")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .opacity(animate ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.1), value: animate)

                            Text("Let's get you started")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .opacity(animate ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.2), value: animate)
                        }
                    }
                }
                .padding(.horizontal, Constants.paddingLarge)

                Spacer()

                // Get Started button
                VStack(spacing: 16) {
                    LiquidGlassCTAButton(
                        text: "Get Started",
                        icon: "arrow.right",
                        action: {
                            viewModel.nextStep()
                        },
                        isEnabled: true
                    )
                    .opacity(animate ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: animate)

                    Text("Takes less than 3 minutes")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.appTextTertiary)
                        .opacity(animate ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.4), value: animate)

                    #if DEBUG
                    if showDebugOptions {
                        Button(
                            action: {
                                // print("🔧 DEBUG: Skipping onboarding via button")
                                UserDefaults.standard.set(true, forKey: Constants.hasCompletedOnboardingKey)

                                // Force update profile to mark as complete
                                Task {
                                    let updates: [String: Any] = [
                                        "name": "Debug User",
                                        "dateOfBirth": Date(),
                                        "height": 70.0,
                                        "heightUnit": "in",
                                        "gender": "Male",
                                        "onboardingCompleted": true
                                    ]
                                    await authManager.updateProfile(updates)
                                }

                                // Trigger UI update
                                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
                            },
                            label: {
                                Text("🔧 Skip Onboarding (Debug)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        )
                        .padding(.top, 16)
                        .transition(.opacity)
                    }
                    #endif
                }
                .padding(.horizontal, Constants.paddingLarge)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            animate = true
        }
        #if DEBUG
        // Debug: Long press to show debug options
        .onLongPressGesture(minimumDuration: 2.0) {
            withAnimation(.spring()) {
                showDebugOptions.toggle()
            }
        }
        #endif
    }
}

#Preview {
    ZStack {
        Color.appBackground
            .ignoresSafeArea()

        WelcomeStepView()
            .environmentObject(OnboardingViewModel())
            .environmentObject(AuthManager())
    }
}
