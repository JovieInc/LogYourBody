//
// WhatsNewView.swift
// LogYourBody
//
import SwiftUI

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.appPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appText)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss)
    private var dismiss
    @State private var selectedVersion: String?

    private let changelogManager = ChangelogManager.shared

    var body: some View {
        NavigationView {
            List {
                ForEach(changelogManager.entries, id: \.version) { entry in
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // Version header
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Version \(entry.version)")
                                        .font(.headline)
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if entry.version == AppVersionManager.shared.currentVersion {
                                    Text("Current")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                            }

                            // Changes
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(entry.changes.enumerated()), id: \.offset) { _, change in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: change.type.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(change.type.color))
                                            .frame(width: 20)

                                        Text(change.description)
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        changelogManager.markAsViewed()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            changelogManager.markAsViewed()
        }
    }
}

#Preview("What's New") {
    WhatsNewView()
}
