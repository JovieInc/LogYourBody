//
// LegalDocumentRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - Legal Document Row Molecule

struct LegalDocumentRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    
    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            value: subtitle,
            showChevron: true
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        LegalDocumentRow(
            icon: "shield.lefthalf.filled",
            title: "GDPR Compliance",
            subtitle: "EU"
        )
        
        DSDivider().insetted(16)
        
        LegalDocumentRow(
            icon: "doc.text",
            title: "Terms of Service"
        )
    }
    .padding()
    .background(Color.appCard)
}
