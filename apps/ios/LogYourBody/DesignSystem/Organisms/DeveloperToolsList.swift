//
// DeveloperToolsList.swift
// LogYourBody
//
import SwiftUI

// MARK: - Developer Tools List Organism

struct DeveloperToolsList: View {
    let tools: [DeveloperTool]
    
    var body: some View {
        SettingsSection(header: "Debug Tools") {
            VStack(spacing: 0) {
                ForEach(tools.indices, id: \.self) { index in
                    Button(action: tools[index].action) {
                        SettingsRow(
                            icon: tools[index].icon,
                            title: tools[index].title,
                            value: tools[index].description,
                            showChevron: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if index < tools.count - 1 {
                        DSDivider().insetted(16)
                    }
                }
            }
        }
    }
    
    // MARK: - Developer Tool Model
    
    struct DeveloperTool {
        let icon: String
        let title: String
        let description: String?
        let action: () -> Void
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DeveloperToolsList(
            tools: [
                .init(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Test Sync",
                    description: nil,
                    action: { /* Test sync action */ }
                ),
                .init(
                    icon: "doc.text.magnifyingglass",
                    title: "View Logs",
                    description: "Last run: 2 mins ago",
                    action: { /* View logs action */ }
                ),
                .init(
                    icon: "trash",
                    title: "Clear Cache",
                    description: nil,
                    action: { /* Clear cache action */ }
                )
            ]
        )
        .padding()
    }
    .background(Color.appBackground)
}
