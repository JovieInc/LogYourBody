//
// DeveloperMenuSection.swift
// LogYourBody
//
import SwiftUI

// MARK: - Organism: Developer Menu Section

struct DeveloperMenuSection: View {
    let isVisible: Bool
    let onNavigate: () -> Void
    
    var body: some View {
        if isVisible {
            VStack(spacing: DesignSystem.spacing.xs) {
                Button(action: onNavigate) {
                    HStack(spacing: DesignSystem.spacing.xs) {
                        Image(systemName: "hammer")
                            .font(DesignSystem.typography.captionSmall)
                        
                        Text("Developer Options")
                            .font(DesignSystem.typography.captionSmall)
                    }
                    .foregroundColor(DesignSystem.colors.primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, DesignSystem.spacing.lg)
            .padding(.bottom, DesignSystem.spacing.xxl)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Spacer()
                .frame(height: 60)
        }
    }
}

// MARK: - Developer Tap Handler

struct DeveloperTapHandler<Content: View>: View {
    @State private var tapCount = 0
    @State private var resetTask: Task<Void, Never>?
    
    let requiredTaps: Int
    let onUnlock: () -> Void
    @ViewBuilder let content: (Int) -> Content
    
    init(
        requiredTaps: Int = 7,
        onUnlock: @escaping () -> Void,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.requiredTaps = requiredTaps
        self.onUnlock = onUnlock
        self.content = content
    }
    
    var body: some View {
        Button(action: handleTap) {
            content(tapCount)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleTap() {
        tapCount += 1
        
        if tapCount >= requiredTaps {
            withAnimation(DesignSystem.animation.spring) {
                onUnlock()
                tapCount = 0
            }
        } else {
            // Cancel previous reset task
            resetTask?.cancel()
            
            // Reset tap count after 3 seconds
            resetTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled && tapCount < requiredTaps {
                    withAnimation {
                        tapCount = 0
                    }
                }
            }
        }
    }
}

// MARK: - Developer Tools List

struct DeveloperToolsList: View {
    let tools: [DeveloperTool]
    
    struct DeveloperTool {
        let id = UUID()
        let icon: String
        let title: String
        let description: String?
        let action: () -> Void
    }
    
    var body: some View {
        SettingsSection(header: "Debug Tools") {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                if index > 0 {
                    DSDivider().insetted(16)
                }
                
                SettingsActionRow(
                    icon: tool.icon,
                    title: tool.title,
                    action: tool.action
                )
            }
        }
    }
}

#if DEBUG
extension DeveloperToolsList {
    static var defaultTools: [DeveloperTool] {
        [
            DeveloperTool(
                icon: "arrow.triangle.2.circlepath",
                title: "Test Body Metrics Sync",
                description: nil,
                action: { /* Testing sync */ }
            ),
            DeveloperTool(
                icon: "doc.text.magnifyingglass",
                title: "Print All Body Metrics",
                description: nil,
                action: { /* Printing metrics */ }
            ),
            DeveloperTool(
                icon: "icloud.and.arrow.up",
                title: "Force Sync Now",
                description: nil,
                action: { /* Forcing sync */ }
            ),
            DeveloperTool(
                icon: "trash",
                title: "Clear Caches",
                description: nil,
                action: { /* Clearing caches */ }
            )
        ]
    }
}
#endif

#Preview {
    VStack(spacing: 20) {
        // Developer menu section
        DeveloperMenuSection(
            isVisible: true,
            onNavigate: { /* Navigate to developer menu */ }
        )
        
        Divider()
        
        // Developer tools list
        #if DEBUG
        DeveloperToolsList(tools: DeveloperToolsList.defaultTools)
        #endif
    }
    .padding()
    .background(Color.black)
}
