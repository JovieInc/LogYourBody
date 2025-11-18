//
// MainTabView.swift
// LogYourBody
//
import SwiftUI

struct MainTabView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            DashboardViewLiquid()
        }
        .onAppear {
            // Check HealthKit authorization status on app launch
            healthKitManager.checkAuthorizationStatus()

            // If sync is enabled and we're authorized, start observers
            if healthKitSyncEnabled && healthKitManager.isAuthorized {
                Task {
                    // Start observers for real-time updates
                    healthKitManager.observeWeightChanges()
                    healthKitManager.observeStepChanges()

                    // Enable background step delivery
                    try? await healthKitManager.setupStepCountBackgroundDelivery()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MainTabView()
            .environmentObject(AuthManager())
    }
}
