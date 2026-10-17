//
// HomeV2SidebarView.swift
// LogYourBody
//
import SwiftUI

/// The MVP root workspaces; photos and entries stay contextual.
enum HomeV2SidebarDestination: String, CaseIterable, Identifiable {
    case today
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return HomeV2Copy.title
        case .progress: return HomeV2ProgressCopy.title
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .progress: return "chart.xyaxis.line"
        }
    }
}

enum HomeV2SidebarCopy {
    static let settings = "Settings"
    static let help = "Help & feedback"
    static let recent = "Recent conversations"
    static let closeSidebar = "Close sidebar"
    static let freePlan = "Free"
    static let proPlan = "Pro"
}

/// Sidebar: profile, Home and Progress, then any available recent conversations.
/// Settings and Help remain at the bottom, over a dimmed Home.
struct HomeV2SidebarView: View {
    let name: String
    let planText: String
    let avatarURL: URL?
    var profileDetail: String?
    let selected: HomeV2SidebarDestination
    let recentConversations: [String]
    let onSelect: (HomeV2SidebarDestination) -> Void
    let onConversation: (String) -> Void
    let onSettings: () -> Void
    let onHelp: () -> Void
    let onClose: () -> Void

    private static let drawerWidth: CGFloat = 306

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel(HomeV2SidebarCopy.closeSidebar)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home_v2_sidebar_scrim")

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                profile
                    .padding(.bottom, HomeV2Tokens.Space.tight)

                ForEach(HomeV2SidebarDestination.allCases) { destination in
                    row(destination)
                }

                if !recentConversations.isEmpty {
                    Text(HomeV2SidebarCopy.recent)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, weight: .medium, relativeTo: .caption)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .padding(.horizontal, HomeV2Tokens.Space.row)
                        .padding(.top, HomeV2Tokens.Space.compact)
                        .padding(.bottom, HomeV2Tokens.Space.tight / 2)

                    ForEach(recentConversations.prefix(3), id: \.self) { title in
                        Button {
                            onConversation(title)
                        } label: {
                            Text(title)
                                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                                .padding(.horizontal, HomeV2Tokens.Space.row)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                quietRow(
                    HomeV2SidebarCopy.settings,
                    systemImage: "gearshape",
                    identifier: "home_v2_sidebar_settings",
                    action: onSettings
                )
                quietRow(HomeV2SidebarCopy.help, systemImage: "lifepreserver", identifier: "home_v2_sidebar_help", action: onHelp)
            }
            .padding(.horizontal, HomeV2Tokens.Space.row)
            .padding(.top, HomeV2Tokens.Space.compact)
            .padding(.bottom, HomeV2Tokens.Space.compact)
            .frame(width: Self.drawerWidth)
            .frame(maxHeight: .infinity)
            .background(HomeV2Tokens.Colors.shell)
        }
        // Observe dismissal swipes without giving the drawer priority over row buttons.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60, abs(value.translation.width) > abs(value.translation.height) {
                    onClose()
                }
            }
        )
    }

    private var profile: some View {
        HStack(spacing: HomeV2Tokens.Space.row) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_sidebar")
                if let profileDetail, !profileDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(profileDetail)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .accessibilityIdentifier("home_v2_sidebar_profile_detail")
                }
                Text(planText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            Spacer(minLength: HomeV2Tokens.Space.tight)
        }
        .padding(.horizontal, HomeV2Tokens.Space.tight)
        .frame(minHeight: 64)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL {
            AsyncImage(url: avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initials
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            initials
        }
    }

    private var initials: some View {
        Text(String(name.prefix(1)).uppercased())
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .frame(width: 36, height: 36)
            .background(HomeV2Tokens.Colors.card, in: Circle())
    }

    private func row(_ destination: HomeV2SidebarDestination) -> some View {
        let isSelected = destination == selected
        return Button {
            onSelect(destination)
        } label: {
            HStack(spacing: HomeV2Tokens.Space.row) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 20)
                Text(destination.title)
                    .scaledSystemFont(
                        size: HomeV2Tokens.TypeSize.body,
                        weight: isSelected ? .semibold : .regular,
                        relativeTo: .body
                    )
                Spacer(minLength: HomeV2Tokens.Space.tight)
            }
            .foregroundStyle(isSelected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary)
            .padding(.horizontal, HomeV2Tokens.Space.row)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .background(
                isSelected ? HomeV2Tokens.Colors.card : Color.clear,
                in: RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("home_v2_sidebar_\(destination.rawValue)")
    }

    private func quietRow(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: HomeV2Tokens.Space.row) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .padding(.horizontal, HomeV2Tokens.Space.row)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
