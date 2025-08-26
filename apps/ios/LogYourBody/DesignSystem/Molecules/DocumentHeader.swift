//
// DocumentHeader.swift
// LogYourBody
//
import SwiftUI

// MARK: - Document Header Molecule

struct DocumentHeader: View {
    let icon: String
    let title: String
    let iconColor: Color
    
    init(
        icon: String,
        title: String,
        iconColor: Color = .appPrimary
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            DSIcon(
                name: icon,
                size: .large,
                color: iconColor
            )
            
            // Title
            DSText(
                title,
                style: .largeTitle,
                weight: .bold,
                color: .appText
            )
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DocumentHeader(
            icon: "doc.text",
            title: "Terms of Service"
        )
        
        DocumentHeader(
            icon: "shield.lefthalf.filled",
            title: "GDPR Compliance",
            iconColor: .success
        )
    }
    .padding()
    .background(Color.appBackground)
}
