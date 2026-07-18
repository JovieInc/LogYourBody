//
// UserGreeting.swift
// LogYourBody
//
import SwiftUI

// MARK: - UserGreeting Molecule

/// Displays a time-based greeting with user's first name
struct UserGreeting: View {
    let fullName: String?
    var showEmoji: Bool = false
    var compactMode: Bool = false
    var customGreeting: String?

    private var greeting: String {
        Self.greeting(at: Date(), showEmoji: showEmoji, customGreeting: customGreeting)
    }

    private var firstName: String {
        Self.firstName(from: fullName)
    }

    static func greeting(
        at date: Date,
        showEmoji: Bool,
        customGreeting: String?,
        calendar: Calendar = .current
    ) -> String {
        if let customGreeting {
            return customGreeting
        }

        let hour = calendar.component(.hour, from: date)
        let baseGreeting: String
        switch hour {
        case 0..<12: baseGreeting = "Good morning"
        case 12..<17: baseGreeting = "Good afternoon"
        default: baseGreeting = "Good evening"
        }

        if showEmoji {
            let emoji: String
            switch hour {
            case 0..<12: emoji = "☀️"
            case 12..<17: emoji = "🌤"
            case 17..<21: emoji = "🌅"
            default: emoji = "🌙"
            }
            return "\(baseGreeting) \(emoji)"
        }

        return baseGreeting
    }

    static func firstName(from fullName: String?) -> String {
        guard let fullName = fullName, !fullName.isEmpty else { return "there" }
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedName.components(separatedBy: " ").filter { !$0.isEmpty }
        return components.first ?? "there"
    }

    var body: some View {
        if compactMode {
            HStack(spacing: 4) {
                Text(greeting)
                    .font(.system(size: 14))
                    .foregroundColor(.appTextSecondary)
                Text(firstName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appText)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)

                Text(firstName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appText)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // Standard greetings
        VStack(alignment: .leading, spacing: 16) {
            Text("Standard Mode").font(.headline).foregroundColor(.appText)
            UserGreeting(fullName: "John Doe")
            UserGreeting(fullName: "Jane")
            UserGreeting(fullName: nil)
            UserGreeting(fullName: "   ") // Empty spaces
        }

        Divider()

        // With emojis
        VStack(alignment: .leading, spacing: 16) {
            Text("With Emojis").font(.headline).foregroundColor(.appText)
            UserGreeting(fullName: "Alice Johnson", showEmoji: true)
            UserGreeting(fullName: "Bob Smith", showEmoji: true)
            UserGreeting(fullName: nil, showEmoji: true)
        }

        Divider()

        // Compact mode
        VStack(alignment: .leading, spacing: 16) {
            Text("Compact Mode").font(.headline).foregroundColor(.appText)
            UserGreeting(fullName: "Charlie Brown", compactMode: true)
            UserGreeting(fullName: "Diana Prince", showEmoji: true, compactMode: true)
            UserGreeting(fullName: nil, compactMode: true)
        }

        Divider()

        // Custom greetings
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Greetings").font(.headline).foregroundColor(.appText)
            UserGreeting(fullName: "Welcome back", customGreeting: "Welcome back")
            UserGreeting(fullName: "VIP User", showEmoji: true, customGreeting: "Hello")
            UserGreeting(fullName: "Admin", compactMode: true, customGreeting: "System ready")
        }
    }
    .padding()
    .background(Color.appBackground)
}
