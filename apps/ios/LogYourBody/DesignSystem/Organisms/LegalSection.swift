//
// LegalSection.swift
// LogYourBody
//
import SwiftUI

// MARK: - Legal Section Organism

struct LegalSection<Destination: View>: View {
    let header: String
    let footer: String?
    let items: [LegalSectionItem<Destination>]
    
    init(
        header: String,
        footer: String? = nil,
        items: [LegalSectionItem<Destination>]
    ) {
        self.header = header
        self.footer = footer
        self.items = items
    }
    
    var body: some View {
        SettingsSection(header: header, footer: footer) {
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    if let destination = items[index].destination {
                        NavigationLink(destination: destination) {
                            LegalDocumentRow(
                                icon: items[index].icon,
                                title: items[index].title,
                                subtitle: items[index].subtitle
                            )
                        }
                    } else if let url = items[index].externalURL {
                        Link(destination: url) {
                            SettingsRow(
                                icon: items[index].icon,
                                title: items[index].title,
                                value: items[index].subtitle,
                                showChevron: true,
                                isExternal: true
                            )
                        }
                    } else {
                        LegalDocumentRow(
                            icon: items[index].icon,
                            title: items[index].title,
                            subtitle: items[index].subtitle
                        )
                    }
                    
                    if index < items.count - 1 {
                        DSDivider().insetted(16)
                    }
                }
            }
        }
    }
}

// MARK: - Legal Section Item

struct LegalSectionItem<Destination: View> {
    let icon: String
    let title: String
    let subtitle: String?
    let destination: Destination?
    let externalURL: URL?
    
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destination: Destination? = nil,
        externalURL: URL? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
        self.externalURL = externalURL
    }
}

// MARK: - Empty View Conformance for Convenience

extension LegalSectionItem where Destination == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        externalURL: URL? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = nil
        self.externalURL = externalURL
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            LegalSection(
                header: "Legal Documents",
                items: [
                    LegalSectionItem(
                        icon: "heart.text.square",
                        title: "Health Disclaimer",
                        destination: Text("Health Disclaimer View")
                    ),
                    LegalSectionItem(
                        icon: "hand.raised",
                        title: "Privacy Policy",
                        destination: Text("Privacy Policy View")
                    )
                ]
            )
            
            LegalSection<EmptyView>(
                header: "Legal Contact",
                items: [
                    LegalSectionItem(
                        icon: "envelope",
                        title: "Legal Inquiries",
                        subtitle: "legal@logyourbody.com",
                        externalURL: URL(string: "mailto:legal@logyourbody.com")
                    )
                ]
            )
        }
        .padding()
    }
    .background(Color.appBackground)
}
