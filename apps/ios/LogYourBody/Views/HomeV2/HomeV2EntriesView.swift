//
// HomeV2EntriesView.swift
// LogYourBody
//
import SwiftUI

/// Entries (Pencil E0): every logged day, one month per section, newest
/// first. A row opens that day in Context. Viewing needs no action.
struct HomeV2EntriesView: View {
    let sections: [HomeV2EntriesSection]
    let onSelect: (Date) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(sections) { section in
                        sectionHeader(section)
                        ForEach(section.rows) { row in
                            entryRow(row)
                        }
                    }
                }
            }
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("home_v2_entries_back")

            Text(HomeV2ContextCopy.entries)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_entries")

            Color.clear
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(minHeight: JovieTokens.compactControlHeight)
    }

    private func sectionHeader(_ section: HomeV2EntriesSection) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: HomeV2Tokens.Space.tight) {
            Text(section.title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .bold, relativeTo: .title2)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Spacer(minLength: HomeV2Tokens.Space.tight)
            if let delta = section.delta {
                Text(delta)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(minHeight: 53)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
    }

    private func entryRow(_ row: HomeV2EntriesRow) -> some View {
        Button {
            onSelect(row.date)
        } label: {
            HStack(spacing: HomeV2Tokens.Space.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.dayText)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                    Text(row.source)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }

                Spacer(minLength: HomeV2Tokens.Space.tight)

                Text(row.valueText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .lineLimit(1)

                if let photoURL = row.photoURL {
                    SubjectPlateView(urlString: photoURL, size: CGSize(width: 28, height: 36))
                        .clipShape(RoundedRectangle(cornerRadius: HomeV2Tokens.thumbRadius, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: 28, height: 36)
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityLabel("\(row.dayText), \(row.valueText), \(row.source)")
        .accessibilityHint("Opens this day")
        .accessibilityIdentifier("home_v2_entries_row")
    }
}
