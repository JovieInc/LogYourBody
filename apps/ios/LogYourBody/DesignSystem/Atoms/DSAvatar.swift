//
// DSAvatar.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSAvatar Atom

/// A circular avatar image with fallback options and optimized performance
struct DSAvatar: View {
    let url: String?
    let name: String?
    var size: CGFloat = 32
    var fontSize: CGFloat = 14
    var backgroundColor: Color = .appPrimary
    var borderColor: Color? = nil
    var borderWidth: CGFloat = 0
    
    private var initials: String {
        guard let name = name, !name.isEmpty else { return "U" }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedName.components(separatedBy: " ")
            .filter { !$0.isEmpty }
        
        if components.count >= 2 {
            let firstInitial = components[0].prefix(1)
            let lastInitial = components[components.count - 1].prefix(1)
            return "\(firstInitial)\(lastInitial)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(1)).uppercased()
        }
        return "U"
    }
    
    var body: some View {
        Group {
            if let urlString = url, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(.white)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure(_):
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .overlay(
            Circle()
                .strokeBorder(borderColor ?? .clear, lineWidth: borderWidth)
        )
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(backgroundColor)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            // Different sizes
            DSAvatar(url: nil, name: "John Doe", size: 24, fontSize: 10)
            DSAvatar(url: nil, name: "Jane Smith", size: 32, fontSize: 14)
            DSAvatar(url: nil, name: "Bob", size: 48, fontSize: 20)
            DSAvatar(url: nil, name: "Alice Johnson", size: 64, fontSize: 28)
        }
        
        HStack(spacing: 20) {
            // With borders
            DSAvatar(
                url: nil,
                name: "Premium User",
                size: 48,
                backgroundColor: .appPrimary,
                borderColor: .white,
                borderWidth: 2
            )
            DSAvatar(
                url: nil,
                name: "Gold Member",
                size: 48,
                backgroundColor: .orange,
                borderColor: .yellow,
                borderWidth: 3
            )
            DSAvatar(
                url: nil,
                name: "VIP",
                size: 48,
                backgroundColor: .purple,
                borderColor: .white.opacity(0.5),
                borderWidth: 1
            )
        }
        
        HStack(spacing: 20) {
            // Edge cases
            DSAvatar(url: nil, name: "   ", size: 48) // Empty spaces
            DSAvatar(url: nil, name: nil, size: 48) // Nil name
            DSAvatar(url: nil, name: "Single", size: 48) // Single name
            DSAvatar(url: nil, name: "Three Name Person", size: 48) // Multiple names
        }
        
        HStack(spacing: 20) {
            // With URL (will show loading indicator)
            DSAvatar(
                url: "https://example.com/avatar.jpg",
                name: "User",
                size: 48
            )
            
            // Invalid URL fallback
            DSAvatar(
                url: "",
                name: "Empty URL",
                size: 48,
                backgroundColor: .red
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}
