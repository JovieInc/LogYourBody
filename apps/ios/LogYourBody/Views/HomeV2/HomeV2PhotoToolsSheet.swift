//
// HomeV2PhotoToolsSheet.swift
// LogYourBody
//
import SwiftUI

/// Photo tools (Pencil P8): every optional photo destination behind one
/// disclosure, with the share boundary spelled out.
struct HomeV2PhotoToolsSheet: View {
    let dateText: String
    let positionText: String
    let onSelect: (HomeV2PhotoTool) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2PhotoCopy.photoTools)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_photo_tools")
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Button(action: onDone) {
                    Text(HomeV2PhotoCopy.done)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_v2_photo_tools_done")
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .frame(minHeight: HomeV2Tokens.rowHeight)

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                Text(dateText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                Text(positionText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.vertical, HomeV2Tokens.Space.margin)

            ForEach(HomeV2PhotoTool.allCases) { tool in
                Button {
                    onSelect(tool)
                } label: {
                    HStack(spacing: HomeV2Tokens.Space.compact) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .frame(width: 20)
                        Text(tool.title)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Spacer(minLength: HomeV2Tokens.Space.tight)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HomeV2Tokens.Colors.quiet)
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.margin)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { HomeV2Hairline().padding(.horizontal, HomeV2Tokens.Space.margin) }
                .accessibilityIdentifier("home_v2_photo_tool_\(tool.identifier)")
            }

            Text(HomeV2PhotoCopy.shareBoundary)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .padding(.vertical, HomeV2Tokens.Space.margin)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeV2Tokens.Colors.elevated)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(HomeV2Tokens.Colors.elevated)
    }
}
