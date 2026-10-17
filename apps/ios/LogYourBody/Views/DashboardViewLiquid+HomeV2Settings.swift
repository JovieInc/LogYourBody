//
// DashboardViewLiquid+HomeV2Settings.swift
// LogYourBody
//
import SwiftUI

extension DashboardViewLiquid {
    var homeV2ProfileName: String {
        let profileName = authManager.currentUser?.profile?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileName, !profileName.isEmpty { return profileName }
        if let name = authManager.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return authManager.currentUser?.email ?? "You"
    }

    /// Profile stores canonical centimetres; display respects the chosen units.
    var homeV2ProfileDetail: String? {
        guard let profile = authManager.currentUser?.profile else { return nil }
        var parts: [String] = []
        if let sex = profile.gender?.trimmingCharacters(in: .whitespacesAndNewlines), !sex.isEmpty {
            parts.append(sex.capitalized)
        }
        if let cm = profile.height, cm.isFinite, cm > 0 {
            parts.append(UnitConversion.formatHeight(cm, useMetric: currentMeasurementSystem == .metric))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var homeV2PlanText: String {
        let manager = SubscriptionManager.shared
        return HomeV2SettingsCopy.planText(
            isSubscribed: manager.isSubscribed,
            productIdentifier: manager.currentSubscriptionProductIdentifier
        )
    }

    var homeV2SidebarSelection: HomeV2SidebarDestination {
        return selectedPhotoTimelineRootPage == .analytics ? .progress : .today
    }

    /// The sidebar (Pencil N1) takes the legacy menu's place under the gate.
    var homeV2Sidebar: some View {
        HomeV2SidebarView(
            name: homeV2ProfileName,
            planText: homeV2PlanText,
            avatarURL: avatarURL,
            profileDetail: homeV2ProfileDetail,
            selected: homeV2SidebarSelection,
            // ponytail: chat history isn't exposed to the dashboard yet; the Ask slice fills this.
            recentConversations: [],
            onSelect: { destination in
                isShowingPhotoTimelineMenu = false
                homeV2Navigate(to: destination)
            },
            onConversation: { _ in },
            onSettings: {
                isShowingPhotoTimelineMenu = false
                isHomeV2SettingsPresented = true
            },
            onHelp: {
                isShowingPhotoTimelineMenu = false
                isHomeV2HelpPresented = true
            },
            onClose: { isShowingPhotoTimelineMenu = false }
        )
        .presentationBackground(.clear)
    }

    func homeV2Navigate(to destination: HomeV2SidebarDestination) {
        HapticManager.shared.selection()
        switch destination {
        case .today:
            selectedPhotoTimelineRootPage = .timeline
            isHomeChatExpanded = false
        case .progress:
            openHomeV2Progress()
        }
    }

    var homeV2SettingsView: some View {
        PreferencesView()
            .environmentObject(authManager)
    }
}
