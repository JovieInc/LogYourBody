//
// UserHeaderSection.swift
// LogYourBody
//
import SwiftUI

// MARK: - User Header Section Organism

struct UserHeaderSection: View {
    let name: String?
    let email: String?
    
    var body: some View {
        VStack(spacing: 16) {
            // User Avatar
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                
                Text(name?.prefix(1).uppercased() ?? "U")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            // User Info
            VStack(spacing: 4) {
                Text(name ?? "User")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let email = email {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        UserHeaderSection(
            name: "John Doe",
            email: "john.doe@example.com"
        )
        
        Divider()
            .padding(.vertical)
        
        UserHeaderSection(
            name: nil,
            email: nil
        )
    }
    .background(Color.appBackground)
}
