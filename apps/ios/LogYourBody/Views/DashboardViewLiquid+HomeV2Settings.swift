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

    var homeV2PlanText: String {
        let manager = SubscriptionManager.shared
        return HomeV2SettingsCopy.planText(
            isSubscribed: manager.isSubscribed,
            productIdentifier: manager.currentSubscriptionProductIdentifier
        )
    }

    var homeV2SidebarSelection: HomeV2SidebarDestination {
        if isHomeChatExpanded || selectedPhotoTimelineRootPage == .chat { return .ask }
        return selectedPhotoTimelineRootPage == .analytics ? .progress : .today
    }

    /// The sidebar (Pencil N1) takes the legacy menu's place under the gate.
    var homeV2Sidebar: some View {
        HomeV2SidebarView(
            name: homeV2ProfileName,
            planText: homeV2PlanText,
            avatarURL: avatarURL,
            photoCount: HomeV2PhotoIndex.photoIndices(in: bodyMetrics).count,
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
        case .photos:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                isHomeV2AllPhotosPresented = true
            }
        case .progress:
            openHomeV2Progress()
        case .entries:
            isHomeV2EntriesPresented = true
        case .ask:
            // Changing the page resets the expanded chat, so Ask expands it on Today.
            selectedPhotoTimelineRootPage = .timeline
            isHomeChatExpanded = true
        }
    }

    var homeV2WeightTargetText: String {
        guard let goal = weightGoal else { return HomeV2SettingsCopy.notSet }
        let value = convertWeight(goal, to: currentMeasurementSystem) ?? goal
        return "\(HomeV2WeightStepPolicy.text(value)) \(homeV2DisplayUnit)"
    }

    var homeV2BodyFatTargetText: String {
        bodyFatGoal.map { String(format: "%.1f%%", $0) } ?? HomeV2SettingsCopy.notSet
    }

    var homeV2SettingsValues: HomeV2SettingsValues {
        let notifications = NotificationManager.shared
        return HomeV2SettingsValues(
            profileName: homeV2ProfileName,
            planText: homeV2PlanText,
            healthText: HealthKitManager.shared.isAuthorized ? HomeV2SettingsCopy.connected : HomeV2SettingsCopy.off,
            unitsText: HomeV2SettingsCopy.unitsText(currentMeasurementSystem),
            targetText: homeV2WeightTargetText,
            remindersText: notifications.isDailyWeighInReminderEnabled
                ? notifications.dailyWeighInDisplayTime
                : HomeV2SettingsCopy.off
        )
    }

    /// Settings (Pencil S1) pushed from the root; S2–S6 push from here.
    var homeV2SettingsView: some View {
        HomeV2SettingsView(
            values: homeV2SettingsValues,
            faceIDLock: $homeV2FaceIDLock,
            onBack: { isHomeV2SettingsPresented = false },
            onRoute: { homeV2SettingsRoute = $0 }
        )
        .navigationDestination(item: $homeV2SettingsRoute) { route in
            homeV2SettingsRouteView(route)
        }
        .sheet(isPresented: $isHomeV2PaywallPresented) {
            PaywallView()
                .environmentObject(authManager)
        }
        .sheet(item: $homeV2GoalEditor) { goal in
            homeV2GoalEditorSheet(for: goal)
        }
    }

    @ViewBuilder
    func homeV2SettingsRouteView(_ route: HomeV2SettingsRoute) -> some View {
        switch route {
        case .profile:
            PreferencesView()
                .environmentObject(authManager)
        case .subscription:
            HomeV2SubscriptionView(
                isSubscribed: SubscriptionManager.shared.isSubscribed,
                planText: homeV2PlanText,
                renewsText: SubscriptionManager.shared.subscriptionExpirationDate.map {
                    HomeV2SettingsCopy.renews(on: formatHUDDate($0), price: nil)
                },
                onBack: { homeV2SettingsRoute = nil },
                onChangePlan: { isHomeV2PaywallPresented = true },
                onRestore: { await SubscriptionManager.shared.restorePurchases() },
                onManage: {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        case .appleHealth:
            IntegrationsView()
                .environmentObject(authManager)
        case .units:
            HomeV2UnitsView(
                system: Binding(
                    get: { currentMeasurementSystem },
                    set: { measurementSystem = $0.rawValue }
                ),
                onBack: { homeV2SettingsRoute = nil }
            )
        case .target:
            HomeV2TargetView(
                weightTargetText: homeV2WeightTargetText,
                bodyFatTargetText: homeV2BodyFatTargetText,
                hasAnyTarget: weightGoal != nil || bodyFatGoal != nil,
                onBack: { homeV2SettingsRoute = nil },
                onEditWeight: { homeV2GoalEditor = .weight },
                onEditBodyFat: { homeV2GoalEditor = .bodyFat },
                onRemove: {
                    customWeightGoalKilograms = nil
                    customBodyFatGoal = nil
                    HapticManager.shared.selection()
                }
            )
        case .reminders:
            HomeV2RemindersView(notificationManager: NotificationManager.shared, onBack: { homeV2SettingsRoute = nil })
        case .exportData:
            ExportDataView()
                .environmentObject(authManager)
        case .deleteAccount:
            DeleteAccountView()
                .environmentObject(authManager)
        }
    }

    func homeV2GoalEditorSheet(for goal: PreferenceGoalKind) -> some View {
        let system = currentMeasurementSystem
        let initial: String
        let unit: String?
        switch goal {
        case .weight:
            initial = weightGoal.map { HomeV2WeightStepPolicy.text(convertWeight($0, to: system) ?? $0) } ?? ""
            unit = homeV2DisplayUnit
        case .bodyFat:
            initial = bodyFatGoal.map { String(format: "%.1f", $0) } ?? ""
            unit = "%"
        case .ffmi:
            initial = ffmiGoal.map { String(format: "%.1f", $0) } ?? ""
            unit = nil
        }
        return PreferenceGoalEditorSheet(goal: goal, initialText: initial, unitLabel: unit) { value in
            switch goal {
            case .weight:
                customWeightGoalKilograms = WeightGoal(displayValue: value, measurementSystem: system)?.kilograms
            case .bodyFat:
                customBodyFatGoal = value
            case .ffmi:
                customFFMIGoal = value
            }
        }
    }
}
