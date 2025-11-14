//
// MainTabView.swift
// LogYourBody
//
import SwiftUI

struct MainTabView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @State private var showAddEntrySheet = false
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        ZStack {
            // Main content
            DashboardViewLiquid()

            // Glass Floating Action Button (FAB)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showAddEntrySheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(20)
                    }
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                    .padding(.trailing, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .sheet(isPresented: $showAddEntrySheet) {
            AddEntrySheet(isPresented: $showAddEntrySheet)
                .environmentObject(authManager)
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
    MainTabView()
        .environmentObject(AuthManager())
        .environmentObject(SyncManager.shared)
}
