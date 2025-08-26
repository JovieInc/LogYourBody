//
// DashboardHeader.swift
// LogYourBody
//
import SwiftUI

// MARK: - DashboardHeader Organism

/// The main header for the dashboard with user info and status indicators
struct DashboardHeader: View {
    let user: User?
    let dailySteps: Int?
    let isSyncing: Bool
    var showLiquidGlass: Bool = true
    var showGreetingEmoji: Bool = false
    var onAvatarTap: (() -> Void)? = nil
    var onStepsTap: (() -> Void)? = nil
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            // Left: Avatar and greeting
            HStack(spacing: 12) {
                DSAvatar(
                    url: user?.avatarUrl,
                    name: user?.profile?.fullName,
                    size: 32
                )
                .onTapGesture {
                    onAvatarTap?()
                }
                
                UserGreeting(
                    fullName: user?.profile?.fullName,
                    showEmoji: showGreetingEmoji
                )
            }
            
            Spacer()
            
            // Right: Status indicators
            HStack(spacing: 16) {
                if let steps = dailySteps {
                    StepsIndicator(steps: steps)
                        .onTapGesture {
                            onStepsTap?()
                        }
                }
                
                if isSyncing {
                    DSCircularProgress(
                        progress: 0.75,
                        size: 20,
                        lineWidth: 2,
                        backgroundColor: .appTextTertiary.opacity(0.3),
                        foregroundColor: .appTextSecondary
                    )
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: isSyncing
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(headerBackground)
        .overlay(headerBorder, alignment: .bottom)
    }
    
    @ViewBuilder
    private var headerBackground: some View {
        if showLiquidGlass {
            if #available(iOS 18.0, *) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(backgroundOpacityColor)
                    )
            } else {
                Rectangle()
                    .fill(backgroundOpacityColor)
            }
        }
    }
    
    @ViewBuilder
    private var headerBorder: some View {
        if showLiquidGlass {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 0.5)
        }
    }
    
    private var backgroundOpacityColor: Color {
        colorScheme == .dark ? Color.appBackground.opacity(0.8) : Color.appBackground.opacity(0.95)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        // With all data and interactions
        DashboardHeader(
            user: PreviewData.mockUser,
            dailySteps: 8_421,
            isSyncing: true,
            onAvatarTap: {
                print("Avatar tapped")
            },
            onStepsTap: {
                print("Steps tapped")
            }
        )
        
        Spacer().frame(height: 20)
        
        // With emoji greeting
        DashboardHeader(
            user: PreviewData.mockUser,
            dailySteps: 15_234,
            isSyncing: false,
            showGreetingEmoji: true
        )
        
        Spacer().frame(height: 20)
        
        // Minimal data
        DashboardHeader(
            user: nil,
            dailySteps: nil,
            isSyncing: false
        )
        
        Spacer().frame(height: 20)
        
        // Without liquid glass
        DashboardHeader(
            user: PreviewData.mockUser,
            dailySteps: 12_500,
            isSyncing: false,
            showLiquidGlass: false
        )
        .background(Color.appCard)
        
        Spacer()
    }
    .background(Color.appBackground)
}

// MARK: - Preview Data

private struct PreviewData {
    static let mockUser = User(
        id: "1",
        email: "john@example.com",
        avatarUrl: nil,
        profile: UserProfile(
            id: "1",
            email: "john@example.com",
            username: "johndoe",
            fullName: "John Doe",
            dateOfBirth: Date(),
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: "moderate",
            goalWeight: 75,
            goalWeightUnit: "kg"
        )
    )
}
