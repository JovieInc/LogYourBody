//
// DSBadge.swift
// LogYourBody
//
import SwiftUI

// MARK: - Atom: Badge

struct DSBadge: View {
    let text: String
    let style: BadgeStyle
    
    enum BadgeStyle {
        case number
        case text
        case subtle
        
        var font: Font {
            switch self {
            case .number, .subtle:
                return .caption2
            case .text:
                return .caption
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .number:
                return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .text, .subtle:
                return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .number:
                return DesignSystem.colors.primary
            case .text:
                return DesignSystem.colors.surface
            case .subtle:
                return DesignSystem.colors.surface.opacity(0.5)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .number:
                return .white
            case .text:
                return DesignSystem.colors.text
            case .subtle:
                return DesignSystem.colors.textSecondary
            }
        }
    }
    
    init(_ text: String, style: BadgeStyle = .text) {
        self.text = text
        self.style = style
    }
    
    var body: some View {
        Text(text)
            .font(style.font)
            .foregroundColor(style.foregroundColor)
            .padding(style.padding)
            .background(
                Capsule()
                    .fill(style.backgroundColor)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        style == .text ? DesignSystem.colors.border : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}

#Preview {
    HStack(spacing: 12) {
        DSBadge("7", style: .number)
        DSBadge("Beta", style: .text)
        DSBadge("Optional", style: .subtle)
    }
    .padding()
    .background(Color.black)
}
