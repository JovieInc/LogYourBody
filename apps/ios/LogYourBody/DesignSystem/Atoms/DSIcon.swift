//
// DSIcon.swift
// LogYourBody
//
import SwiftUI

// MARK: - Design System Icon Atom

struct DSIcon: View {
    let name: String
    let size: IconSize
    let color: Color
    
    enum IconSize {
        case small
        case medium
        case large
        case xlarge
        
        var fontSize: Font {
            switch self {
            case .small: return .caption
            case .medium: return .body
            case .large: return .title2
            case .xlarge: return .largeTitle
            }
        }
    }
    
    init(
        name: String,
        size: IconSize = .medium,
        color: Color = .appPrimary
    ) {
        self.name = name
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Image(systemName: name)
            .font(size.fontSize)
            .foregroundColor(color)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        DSIcon(name: "star.fill", size: .small)
        DSIcon(name: "star.fill", size: .medium)
        DSIcon(name: "star.fill", size: .large)
        DSIcon(name: "star.fill", size: .xlarge)
        DSIcon(name: "heart.fill", size: .large, color: .red)
    }
    .padding()
    .background(Color.appBackground)
}
