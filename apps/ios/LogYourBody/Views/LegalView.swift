//
// LegalView.swift
// LogYourBody
//
import SwiftUI

// MARK: - Refactored Legal View using Atomic Design

struct LegalView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Organisms: Legal Sections
                    legalDocumentsSection
                    complianceSection
                    openSourceSection
                    contactSection
                    
                    // Atom: Footer Text
                    lastUpdatedFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Legal Sections

extension LegalView {
    private var legalDocumentsSection: some View {
        LegalSection(
            header: "Legal Documents",
            items: [
                LegalSectionItem(
                    icon: "heart.text.square",
                    title: "Health Disclaimer",
                    destination: LegalDocumentView(documentType: .healthDisclosure)
                ),
                LegalSectionItem(
                    icon: "hand.raised",
                    title: "Privacy Policy",
                    destination: LegalDocumentView(documentType: .privacy)
                ),
                LegalSectionItem(
                    icon: "doc.text",
                    title: "Terms of Service",
                    destination: LegalDocumentView(documentType: .terms)
                )
            ]
        )
    }
    
    private var complianceSection: some View {
        LegalSection(
            header: "Compliance",
            items: [
                LegalSectionItem(
                    icon: "shield.lefthalf.filled",
                    title: "GDPR Compliance",
                    subtitle: "EU",
                    destination: LegalDocumentView(documentType: .gdprCompliance)
                ),
                LegalSectionItem(
                    icon: "shield.righthalf.filled",
                    title: "CCPA Compliance",
                    subtitle: "California",
                    destination: LegalDocumentView(documentType: .ccpaCompliance)
                )
            ]
        )
    }
    
    private var openSourceSection: some View {
        LegalSection(
            header: "Open Source",
            footer: "LogYourBody uses open source software. Tap to view licenses.",
            items: [
                LegalSectionItem(
                    icon: "text.badge.checkmark",
                    title: "Open Source Licenses",
                    destination: LegalDocumentView(documentType: .openSourceLicenses)
                )
            ]
        )
    }
    
    private var contactSection: some View {
        SettingsSection(header: "Legal Contact") {
            VStack(spacing: 0) {
                // Email Link
                Link(destination: URL(string: "mailto:legal@logyourbody.com")!) {
                    SettingsRow(
                        icon: "envelope",
                        title: "Legal Inquiries",
                        value: "legal@logyourbody.com",
                        showChevron: true,
                        isExternal: true
                    )
                }
                
                DSDivider().insetted(16)
                
                // Mailing Address
                SettingsRow(
                    icon: "location",
                    title: "Mailing Address",
                    value: "View",
                    showChevron: false
                )
            }
        }
    }
    
    private var lastUpdatedFooter: some View {
        DSText(
            "Last updated: \(Date().formatted(date: .abbreviated, time: .omitted))",
            style: .caption,
            color: .appTextTertiary
        )
        .padding(.top, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        LegalView()
    }
    .preferredColorScheme(.dark)
}
