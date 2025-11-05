//
// MainTabView.swift
// LogYourBody
//
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = AnimatedTabView.Tab.dashboard
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @Namespace private var namespace
    @State private var showAddEntrySheet = false
    @EnvironmentObject var authManager: AuthManager
    
    init() {
        // Hide default tab bar since we're using custom one
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content with smooth transitions
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardViewLiquid()
                case .log:
                    // Don't show any content for log tab - it's action-only
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Tab Bar - centered with fixed width
            AnimatedTabView(selectedTab: $selectedTab)
                .frame(width: 200) // Fixed width for compact look
                .padding(.bottom, 20) // Space from bottom edge
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        .onChange(of: selectedTab) { oldValue, newValue in
            // Handle Log tab tap - show sheet and revert to previous tab
            if newValue == .log {
                showAddEntrySheet = true
                // Revert to previous tab (or dashboard if no previous)
                selectedTab = oldValue == .log ? .dashboard : oldValue
            }
        }
        // Toast presenter removed - handle notifications at view level
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
}
