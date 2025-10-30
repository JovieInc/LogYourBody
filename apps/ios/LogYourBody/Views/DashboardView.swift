//
// DashboardView.swift
// LogYourBody
//
import SwiftUI
import HealthKit
import PhotosUI

struct DashboardView: View {
    // MARK: - Properties
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager
    @StateObject var healthKitManager = HealthKitManager.shared
    @StateObject var backgroundTaskMonitor = BackgroundTaskMonitor.shared
    
    @State var dailyMetrics: DailyMetrics?
    @State var selectedDateMetrics: DailyMetrics?
    @State var bodyMetrics: [BodyMetrics] = []
    @State var selectedIndex: Int = 0
    @State var isLoading = false
    @State var hasLoadedInitialData = false
    @State private var refreshID = UUID()
    @State var showPhotoOptions = false
    @State var showCamera = false
    @State var showPhotoPicker = false
    @State var selectedPhoto: PhotosPickerItem?
    @State var showingModal = false
    @Namespace private var namespace
    @AppStorage(Constants.preferredMeasurementSystemKey)
    var measurementSystem = PreferencesView.defaultMeasurementSystem
    
    // MARK: - Computed Properties
    
    var currentSystem: PreferencesView.MeasurementSystem {
        PreferencesView.MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }
    
    var currentMetric: BodyMetrics? {
        guard !bodyMetrics.isEmpty && selectedIndex >= 0 && selectedIndex < bodyMetrics.count else { return nil }
        return bodyMetrics[selectedIndex]
    }
    
    var userAge: Int? {
        guard let dateOfBirth = authManager.currentUser?.profile?.dateOfBirth else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year
    }
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom Header
                    headerView

                    contentView
                }

                // Background Task Banner - appears below header
                VStack {
                    if backgroundTaskMonitor.isAnyTaskActive {
                        DashboardTaskBanner(taskMonitor: backgroundTaskMonitor)
                    }
                    Spacer()
                }
                .padding(.top, 60) // Below header height
            }
            .navigationBarHidden(true)
            .id(refreshID)
            .onChange(of: showPhotoOptions) { _, newValue in
                showingModal = newValue
            }
            .onChange(of: showCamera) { _, newValue in
                showingModal = newValue
            }
            .onChange(of: showPhotoPicker) { _, newValue in
                showingModal = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in
                refreshID = UUID()
            }
            .onAppear {
                // Log the current authentication state
                // print("🎯 DashboardView onAppear")
                // print("   - isAuthenticated: \(authManager.isAuthenticated)")
                // print("   - currentUser: \(authManager.currentUser?.id ?? "nil") (\(authManager.currentUser?.email ?? "nil"))")
                // print("   - clerkSession: \(authManager.clerkSession?.id ?? "nil")")
                
                // Load cached data immediately for instant UI
                if authManager.currentUser?.id != nil {
                    loadCachedDataImmediately()
                    loadDailyMetrics()
                    
                    // Then sync remote data in background
                    Task {
                        // Sync today's steps from HealthKit if authorized
                        if await healthKitManager.isAuthorized {
                            await syncStepsFromHealthKit()
                            
                            // On first launch, sync historical step data
                            if !UserDefaults.standard.bool(forKey: "HasSyncedHistoricalSteps") {
                                await syncHistoricalSteps()
                            }
                        }
                        
                        await loadBodyMetrics()
                    }
                } else {
                    // print("⚠️ No current user on appear")
                }
            }
            .onChange(of: healthKitManager.todayStepCount) { _, newStepCount in
                // print("📱 Step count changed from HealthKit: \(newStepCount)")
                Task {
                    await updateStepCount(newStepCount)
                }
            }
            .sheet(isPresented: $showPhotoOptions) {
                PhotoOptionsSheet(
                    showCamera: $showCamera,
                    showPhotoPicker: $showPhotoPicker
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    Task {
                        await handlePhotoCapture(image)
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    await handlePhotoSelection(newItem)
                }
            }
            .onChange(of: authManager.currentUser?.id) { _, newUserId in
                // print("👤 User ID changed: \(authManager.currentUser?.id ?? "nil") -> \(newUserId ?? "nil")")
                
                // Reset state
                bodyMetrics = []
                dailyMetrics = nil
                selectedDateMetrics = nil
                selectedIndex = 0
                
                // Reload data for new user
                if newUserId != nil {
                    loadCachedDataImmediately()
                    loadDailyMetrics()
                    Task {
                        if healthKitManager.isAuthorized {
                            await syncStepsFromHealthKit()
                        }
                        await loadBodyMetrics()
                    }
                }
            }
        }
    }
}
