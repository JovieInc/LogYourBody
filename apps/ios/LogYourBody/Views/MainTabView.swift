//
// MainTabView.swift
// LogYourBody
//
import SwiftUI

struct MainTabView: View {
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            DashboardViewLiquid()
        }
        .onAppear {
            HealthSyncCoordinator.shared.bootstrapIfNeeded(syncEnabled: healthKitSyncEnabled)
        }
    }
}

#Preview {
    NavigationStack {
        MainTabView()
            .environmentObject(AuthManager())
    }
}
