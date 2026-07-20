//
// LegalDocumentView.swift
// LogYourBody
//
import SwiftUI

// MARK: - Legal Document Loading

enum LegalDocumentLoader {
    static func loadMarkdown(
        for documentType: LegalDocumentView.LegalDocumentType,
        in bundle: Bundle = .main
    ) -> String {
        // Try to load from Resources/Legal directory in bundle
        if let bundlePath = bundle.path(forResource: "Legal/\(documentType.filename)", ofType: "md"),
           let content = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
            return content
        }

        // Try alternate path without subfolder
        if let bundlePath = bundle.path(forResource: documentType.filename, ofType: "md", inDirectory: "Legal"),
           let content = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
            return content
        }

        // Try without any directory
        if let bundlePath = bundle.path(forResource: documentType.filename, ofType: "md"),
           let content = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
            return content
        }

        // Fallback: embedded placeholder content
        return fallbackMarkdown(for: documentType)
    }

    static func fallbackMarkdown(for documentType: LegalDocumentView.LegalDocumentType) -> String {
        switch documentType {
        case .terms:
            return """
            # Terms of Service

            **Last Updated: July 11, 2025**

            We couldn't load the full Terms of Service on this device.

            By using LogYourBody, you agree to our terms and conditions.
            If you need a full copy of the latest Terms, contact \(ProductRegistry.supportEmail).
            """
        case .privacy:
            return """
            # Privacy Policy

            **Last Updated: July 11, 2025**

            We couldn't load the full Privacy Policy on this device.

            We are committed to protecting your privacy and personal data.
            If you need a full copy of the latest Privacy Policy, contact \(ProductRegistry.supportEmail).
            """
        case .healthDisclosure:
            return """
            # Health Disclosure

            **Last Updated: July 11, 2025**

            We couldn't load the full Health Disclosure on this device.

            LogYourBody is not a medical service and does not provide medical advice.
            If you need a full copy of the latest Health Disclosure, contact \(ProductRegistry.supportEmail).
            """
        case .gdprCompliance:
            return """
            # GDPR Compliance

            **Last Updated: July 14, 2025**

            We couldn't load the full GDPR Compliance information on this device.

            We comply with the General Data Protection Regulation for EU users.
            If you need a full copy of the latest GDPR compliance document, contact \(ProductRegistry.supportEmail).
            """
        case .ccpaCompliance:
            return """
            # CCPA Compliance

            **Last Updated: July 14, 2025**

            We couldn't load the full CCPA Compliance information on this device.

            We respect the privacy rights of California residents.
            If you need a full copy of the latest CCPA compliance document, contact \(ProductRegistry.supportEmail).
            """
        case .openSourceLicenses:
            return """
            # Open Source Licenses

            **Last Updated: July 14, 2025**

            We couldn't load the full list of open source licenses on this device.

            LogYourBody is built with amazing open source software.
            If you need a full copy of the latest license list, contact \(ProductRegistry.supportEmail).
            """
        }
    }
}

// MARK: - Refactored Legal Document View using Atomic Design

struct LegalDocumentView: View {
    let documentType: LegalDocumentType
    @State private var documentContent: String = ""
    @State private var isLoading = true
    @State private var loadError = false
    @Environment(\.dismiss) var dismiss

    enum LegalDocumentType: CaseIterable {
        case terms
        case privacy
        case healthDisclosure
        case gdprCompliance
        case ccpaCompliance
        case openSourceLicenses

        var title: String {
            switch self {
            case .terms: return "Terms of Service"
            case .privacy: return "Privacy Policy"
            case .healthDisclosure: return "Health Disclosure"
            case .gdprCompliance: return "GDPR Compliance"
            case .ccpaCompliance: return "CCPA Compliance"
            case .openSourceLicenses: return "Open Source Licenses"
            }
        }

        var filename: String {
            switch self {
            case .terms: return "terms-of-service"
            case .privacy: return "privacy-policy"
            case .healthDisclosure: return "health-disclosure"
            case .gdprCompliance: return "gdpr-compliance"
            case .ccpaCompliance: return "ccpa-compliance"
            case .openSourceLicenses: return "open-source-licenses"
            }
        }

        var icon: String {
            switch self {
            case .terms: return "doc.text"
            case .privacy: return "hand.raised"
            case .healthDisclosure: return "heart.text.square"
            case .gdprCompliance: return "shield.lefthalf.filled"
            case .ccpaCompliance: return "shield.righthalf.filled"
            case .openSourceLicenses: return "text.badge.checkmark"
            }
        }
    }

    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()

            if isLoading {
                // Atom: Loading Indicator
                DSLoadingIndicator(message: "Loading...")
            } else if loadError {
                // Molecule: Error State
                ErrorStateView(
                    title: "Unable to load document",
                    buttonAction: loadDocument
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Molecule: Document Header
                        DocumentHeader(
                            icon: documentType.icon,
                            title: documentType.title
                        )
                        .padding(.top, 20)
                        .padding(.horizontal)

                        // Organism: Markdown Content
                        MarkdownView(markdown: documentContent)
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationTitle(documentType.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDocument()
        }
    }

    private func loadDocument() {
        isLoading = true
        loadError = false
        documentContent = LegalDocumentLoader.loadMarkdown(for: documentType)
        isLoading = false
    }
}

// MARK: - Preview

#Preview("Terms of Service") {
    NavigationStack {
        LegalDocumentView(documentType: .terms)
    }
    .preferredColorScheme(.dark)
}

#Preview("Privacy Policy") {
    NavigationStack {
        LegalDocumentView(documentType: .privacy)
    }
    .preferredColorScheme(.dark)
}

#Preview("Health Disclosure") {
    NavigationStack {
        LegalDocumentView(documentType: .healthDisclosure)
    }
    .preferredColorScheme(.dark)
}
