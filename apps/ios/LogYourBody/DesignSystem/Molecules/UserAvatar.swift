//
// UserAvatar.swift
// LogYourBody
//
import SwiftUI

// MARK: - Molecule: User Avatar

struct UserAvatar: View {
    let name: String?
    let email: String?
    let size: AvatarSize
    let showBorder: Bool
    
    enum AvatarSize {
        case small
        case medium
        case large
        case extraLarge
        
        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 64
            case .extraLarge: return 80
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 20
            case .large: return 28
            case .extraLarge: return 32
            }
        }
    }
    
    init(
        name: String? = nil,
        email: String? = nil,
        size: AvatarSize = .medium,
        showBorder: Bool = false
    ) {
        self.name = name
        self.email = email
        self.size = size
        self.showBorder = showBorder
    }
    
    private var initials: String {
        if let name = name, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        } else if let email = email, !email.isEmpty {
            return String(email.prefix(1)).uppercased()
        }
        return "U"
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.colors.surface)
                .overlay(
                    Circle()
                        .strokeBorder(
                            showBorder ? DesignSystem.colors.border : Color.clear,
                            lineWidth: showBorder ? 2 : 0
                        )
                )
            
            Text(initials)
                .font(.system(size: size.fontSize, weight: .semibold))
                .foregroundColor(DesignSystem.colors.textSecondary)
        }
        .frame(width: size.dimension, height: size.dimension)
    }
}

// MARK: - Avatar with Info

struct UserAvatarWithInfo: View {
    let name: String?
    let email: String?
    let avatarSize: UserAvatar.AvatarSize
    
    var body: some View {
        HStack(spacing: DesignSystem.spacing.sm) {
            UserAvatar(
                name: name,
                email: email,
                size: avatarSize
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? "User")
                    .font(DesignSystem.typography.labelLarge)
                    .foregroundColor(DesignSystem.colors.text)
                
                if let email = email {
                    Text(email)
                        .font(DesignSystem.typography.captionMedium)
                        .foregroundColor(DesignSystem.colors.textSecondary)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Different sizes
        HStack(spacing: 16) {
            UserAvatar(name: "John Doe", size: .small)
            UserAvatar(name: "Jane Smith", size: .medium)
            UserAvatar(name: "Bob Wilson", size: .large)
            UserAvatar(name: "Alice Brown", size: .extraLarge)
        }
        
        // With border
        UserAvatar(name: "Test User", size: .large, showBorder: true)
        
        // With info
        UserAvatarWithInfo(
            name: "John Doe",
            email: "john.doe@example.com",
            avatarSize: .medium
        )
    }
    .padding()
    .background(Color.black)
}
