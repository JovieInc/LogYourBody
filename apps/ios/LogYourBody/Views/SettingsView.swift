//
// SettingsView.swift
// LogYourBody
//
import SwiftUI
import Foundation

// MARK: - Refactored Settings View using Atomic Design

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showDeveloperMenu = false
    @State private var refreshID = UUID()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Atom: Background Color
                Color.appBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Organism: User Header
                        UserHeaderSection(
                            name: authManager.currentUser?.profile?.fullName,
                            email: authManager.currentUser?.email
                        )
                        .padding(.bottom, 30)
                        
                        // Organisms: Settings Sections
                        VStack(spacing: 20) {
                            profileSection
                            preferencesSection
                            integrationsSection
                            securitySection
                            dataPrivacySection
                            legalSection
                            aboutSection
                            
                            // Molecule: Logout Button
                            LogoutButton {
                                Task {
                                    await authManager.logout()
                                }
                            }
                            .padding(.top, 12)
                            
                            // Developer Footer
                            if showDeveloperMenu {
                                VStack(spacing: 8) {
                                    NavigationLink(destination: DeveloperMenuView()) {
                                        HStack {
                                            Image(systemName: "hammer")
                                                .font(.caption2)
                                            Text("Developer Options")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.appPrimary)
                                    }
                                }
                                .padding(.top, 20)
                                .padding(.bottom, 40)
                            } else {
                                // Just add spacing when developer menu is hidden
                                Spacer()
                                    .frame(height: 60)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .id(refreshID)
            .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in
                refreshID = UUID()
            }
        }
    }
}

// MARK: - Settings Sections

extension SettingsView {
    private var profileSection: some View {
        SettingsSection(header: "Profile") {
            SettingsRow(
                icon: "envelope",
                title: "Email",
                value: authManager.currentUser?.email ?? "",
                showChevron: false
            )
            
            DSDivider().insetted(16)
            
            NavigationLink(destination: ProfileSettingsViewV2().environmentObject(authManager)) {
                SettingsRow(
                    icon: "person.circle",
                    title: "Profile Settings",
                    showChevron: true
                )
            }
        }
    }
    
    private var preferencesSection: some View {
        SettingsSection(header: "Preferences") {
            NavigationLink(destination: PreferencesView().environmentObject(authManager)) {
                SettingsRow(
                    icon: "slider.horizontal.3",
                    title: "Units & Security",
                    showChevron: true
                )
            }
        }
    }
    
    private var integrationsSection: some View {
        SettingsSection(header: "Integrations") {
            NavigationLink(destination: IntegrationsView().environmentObject(authManager)) {
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Apps & Import",
                    value: "Apple Health, Photos",
                    showChevron: true
                )
            }
        }
    }
    
    private var securitySection: some View {
        SettingsSection(header: "Security & Devices") {
            NavigationLink(destination: SecuritySessionsView()) {
                SettingsRow(
                    icon: "desktopcomputer",
                    title: "Active Sessions",
                    showChevron: true
                )
            }
            
            DSDivider().insetted(16)
            
            NavigationLink(destination: ChangePasswordView()) {
                SettingsRow(
                    icon: "lock.rotation",
                    title: "Change Password",
                    showChevron: true
                )
            }
        }
    }
    
    private var dataPrivacySection: some View {
        SettingsSection(header: "Data & Privacy") {
            NavigationLink(destination: ExportDataView()) {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    title: "Export Data",
                    showChevron: true
                )
            }
            
            DSDivider().insetted(16)
            
            NavigationLink(destination: DeleteAccountView()) {
                SettingsRow(
                    icon: "trash",
                    title: "Delete Account",
                    showChevron: true,
                    tintColor: .error
                )
            }
        }
    }
    
    private var legalSection: some View {
        SettingsSection(header: "Legal") {
            NavigationLink(destination: LegalView()) {
                SettingsRow(
                    icon: "scale.3d",
                    title: "Legal & Policies",
                    showChevron: true
                )
            }
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(header: "About") {
            // Developer tap handler with version row
            DeveloperTapHandler(
                onUnlock: {
                    withAnimation {
                        showDeveloperMenu = true
                    }
                },
                content: { tapCount in
                HStack {
                    VersionRow()
                    
                    if tapCount > 0 && tapCount < 7 {
                        Spacer()
                        DeveloperTapIndicator(
                            remainingTaps: 7 - tapCount
                        )
                        .padding(.trailing, 16)
                    }
                }
                }
            )
            
            DSDivider().insetted(16)
            
            WhatsNewRow()
            
            DSDivider().insetted(16)
            
            Link(destination: URL(string: "https://logyourbody.com/support")!) {
                SettingsRow(
                    icon: "questionmark.circle",
                    title: "Support",
                    showChevron: true,
                    isExternal: true
                )
            }
        }
    }
}

// MARK: - Developer Menu View (Refactored)

struct DeveloperMenuView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    #if DEBUG
                    // Use the developer tools list organism
                    DeveloperToolsList(tools: developerTools)
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Developer Options")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    #if DEBUG
    private var developerTools: [DeveloperToolsList.DeveloperTool] {
        [
            .init(
                icon: "arrow.triangle.2.circlepath",
                title: "Test Body Metrics Sync",
                description: nil,
                action: {
                    Task {
                        await testBodyMetricsSync()
                    }
                }
            ),
            .init(
                icon: "doc.text.magnifyingglass",
                title: "Print All Body Metrics",
                description: nil,
                action: {
                    CoreDataManager.shared.debugPrintAllBodyMetrics()
                }
            ),
            .init(
                icon: "icloud.and.arrow.up",
                title: "Force Sync Now",
                description: nil,
                action: {
                    SyncManager.shared.syncAll()
                }
            ),
            .init(
                icon: "trash",
                title: "Clear Caches",
                description: nil,
                action: {
                    UserDefaults.standard.removeObject(forKey: "HasSyncedHistoricalSteps")
                }
            )
        ]
    }
    
    @MainActor
    func testBodyMetricsSync() async {
        let testMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: AuthManager.shared.currentUser?.id ?? "",
            date: Date(),
            weight: 75.5,
            weightUnit: "kg",
            bodyFatPercentage: 20.5,
            bodyFatMethod: "Debug Test",
            muscleMass: nil,
            boneMass: nil,
            notes: "Test metric created for debugging sync",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: Date(),
            updatedAt: Date()
        )
        
        CoreDataManager.shared.saveBodyMetrics(testMetric, userId: testMetric.userId, markAsSynced: false)
        SyncManager.shared.syncIfNeeded()
    }
    #endif
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
