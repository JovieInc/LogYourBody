//
// NotificationsStepView.swift
// LogYourBody
//
import SwiftUI
import UserNotifications

struct NotificationsStepView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var animateTitle = false
    @State private var animateBenefits = false
    @State private var animateButton = false
    
    var body: some View {
        ZStack {
            // Edge-to-edge background
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Liquid Glass effect
                HStack {
                    Button(
            action: {
                        viewModel.previousStep()
                        // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
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
                    
                    LiquidGlassSecondaryCTAButton(
                        text: "Skip",
                        action: {
                            viewModel.nextStep()
                        }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                Spacer()
                
                VStack(spacing: 48) {
                    // Icon with subtle animation
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .blur(radius: 20)
                        
                        Image(systemName: "bell.badge")
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(.white)
                            .opacity(animateTitle ? 0.9 : 0)
                            .scaleEffect(animateTitle ? 1 : 0.8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animateTitle)
                    }
                    
                    // Title and subtitle
                    VStack(spacing: 12) {
                        Text("Stay on Track")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.appText)
                            .opacity(animateTitle ? 1 : 0)
                            .offset(y: animateTitle ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: animateTitle)
                        
                        Text("Get gentle reminders to log your progress")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .opacity(animateTitle ? 1 : 0)
                            .offset(y: animateTitle ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: animateTitle)
                    }
                    
                    // Benefits with Liquid Glass cards
                    VStack(spacing: 12) {
                        NotificationBenefitCard(
                            icon: "sun.max",
                            title: "Morning Check-ins",
                            description: "Start your day with a quick weight log",
                            delay: 0.3
                        )
                        .opacity(animateBenefits ? 1 : 0)
                        .offset(y: animateBenefits ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: animateBenefits)
                        
                        NotificationBenefitCard(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Weekly Insights",
                            description: "See your progress trends and stay motivated",
                            delay: 0.4
                        )
                        .opacity(animateBenefits ? 1 : 0)
                        .offset(y: animateBenefits ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: animateBenefits)
                        
                        NotificationBenefitCard(
                            icon: "trophy",
                            title: "Milestone Celebrations",
                            description: "Get notified when you hit your goals",
                            delay: 0.5
                        )
                        .opacity(animateBenefits ? 1 : 0)
                        .offset(y: animateBenefits ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: animateBenefits)
                    }
                    .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // Bottom buttons with Liquid Glass
                VStack(spacing: 20) {
                    LiquidGlassCTAButton(
                        text: "Enable Notifications",
                        icon: "bell.badge",
                        action: requestNotificationPermission,
                        isEnabled: true
                    )
                    .opacity(animateButton ? 1 : 0)
                    .offset(y: animateButton ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: animateButton)
                    
                    Text("You can change this anytime in Settings")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.appTextTertiary)
                        .opacity(animateButton ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.7), value: animateButton)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            checkNotificationStatus()
            animateTitle = true
            animateBenefits = true
            animateButton = true
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }
    
    private func requestNotificationPermission() {
        // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                viewModel.data.notificationsEnabled = granted
                if granted {
                    // HapticManager.shared.successAction() // TODO: Add HapticManager to Xcode project
                }
                viewModel.nextStep()
            }
        }
    }
}

struct NotificationBenefitCard: View {
    let icon: String
    let title: String
    let description: String
    let delay: Double
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon with glass background
            ZStack {
                if #available(iOS 18.0, *) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.05))
                        )
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                }
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.appText)
                
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(16)
        .modifier(NotificationCardModifier())
    }
}

struct NotificationCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.02))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                )
        }
    }
}

#if DEBUG
struct NotificationsStepView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsStepView()
            .environmentObject(OnboardingViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif
