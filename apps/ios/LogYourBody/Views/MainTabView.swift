//
// MainTabView.swift
// LogYourBody
//
import SwiftUI
import CoreData

struct MainTabView: View {
    @AppStorage(Constants.healthKitSyncEnabledKey) private var healthKitSyncEnabled = true
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @State private var selectedSurface: PaidAppSurface = PaidAppSurfacePolicy.surface()

    var body: some View {
        Group {
            if shouldOpenChatFirst {
                ChatFirstRootView()
            } else {
                NavigationStack {
                    switch selectedSurface {
                    case .chatFirst:
                        ChatFirstRootView()
                    case .photoTimelineHUD:
                        DashboardViewLiquid(layoutMode: .photoTimelineHUD)
                    case .legacyFullDashboardBeta:
                        DashboardViewLiquid(layoutMode: .legacyTabbed)
                    case .weightLoggerMVP:
                        PaidWeightLoggerMVPView()
                    }
                }
            }
        }
        .onAppear {
            updateSelectedSurface()
        }
    }

    private var shouldOpenChatFirst: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lybUITestChatFirstFixture") {
            return true
        }

        if arguments.contains(where: { $0.hasPrefix("-lybUITest") }) {
            return false
        }
        #endif

        return true
    }

    private func updateSelectedSurface() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lybUITestWeightLoggerMVPFixture") {
            selectedSurface = .weightLoggerMVP
            return
        }

        if arguments.contains("-lybUITestPhotoTimelineHUDFixture") {
            selectedSurface = .photoTimelineHUD
            return
        }

        if arguments.contains("-lybUITestFullDashboardFixture") {
            selectedSurface = .legacyFullDashboardBeta
            return
        }
        #endif

        selectedSurface = PaidAppSurfacePolicy.surface()

        HealthSyncCoordinator.shared.bootstrapIfNeeded(syncEnabled: healthKitSyncEnabled)
    }
}

private struct PaidWeightLoggerMVPView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var realtimeSyncManager: RealtimeSyncManager
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @State private var weightText = ""
    @State private var recentMetrics: [BodyMetrics] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var exportFileURL: URL?
    @FocusState private var isWeightFieldFocused: Bool

    private var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    private var latestWeight: BodyMetrics? {
        recentMetrics.first
    }

    private var isSaveDisabled: Bool {
        !PaidWeightLoggerMVPPolicy.canSaveWeight(
            weightText: weightText,
            unit: currentSystem.weightUnit,
            isSaving: isSaving
        )
    }

    private var weightValidationMessage: String? {
        PaidWeightLoggerMVPPolicy.validationMessage(
            weightText: weightText,
            unit: currentSystem.weightUnit
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                latestWeightCard
                entryCard
                recentHistorySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("LogYourBody")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    PreferencesView()
                        .environmentObject(authManager)
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens account and subscription settings.")
                .accessibilityIdentifier("mvp_settings_button")

                Menu {
                    Button(role: .destructive) {
                        Task {
                            await authManager.logout()
                        }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("mvp_sign_out_button")
                } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Account")
                .accessibilityIdentifier("mvp_account_menu_button")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Button("Done") {
                    isWeightFieldFocused = false
                }
                .accessibilityIdentifier("mvp_keyboard_done_button")

                Spacer()

                Button(isSaving ? "Saving" : "Save weight") {
                    saveWeight()
                }
                .disabled(isSaveDisabled)
                .accessibilityIdentifier("mvp_keyboard_save_weight_button")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isWeightFieldFocused {
                keyboardSaveBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isWeightFieldFocused)
        .task {
            await loadRecentMetrics()
        }
        .onChange(of: measurementSystem) { _, _ in
            exportFileURL = nil
            savedMessage = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
            Task {
                await loadRecentMetrics()
            }
        }
        .alert("Could not save weight", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight log")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.appText)

            Text("Log today's weight. Your entries stay on this device and sync to your account.")
                .font(.body.weight(.medium))
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var latestWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latest", systemImage: "scalemass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                syncStatusLabel
            }

            if isLoading {
                ProgressView()
                    .tint(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else if let latestWeight, let weight = latestWeight.weight {
                let display = displayWeight(weight)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(display.value)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundColor(.appText)

                        Text(display.unit)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.appTextSecondary)
                    }

                    Text(latestWeight.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.appTextSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No weight yet")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.appText)

                    Text("Add one entry to start the log.")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(Constants.cornerRadiusLarge)
    }

    private var syncStatusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 7, height: 7)

            Text(syncStatusText)
                .font(.caption.weight(.semibold))
                .foregroundColor(.appTextSecondary)
        }
        .accessibilityIdentifier("mvp_sync_status")
    }

    private var keyboardSaveBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.appBorder)

            HStack(spacing: 12) {
                Button("Done") {
                    isWeightFieldFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.appTextSecondary)
                .accessibilityIdentifier("mvp_keyboard_bottom_done_button")

                Button(action: saveWeight) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        }

                        Text(isSaving ? "Saving" : "Save weight")
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(.black)
                    .background(isSaveDisabled ? Color.appBorder : Color.appPrimary)
                    .cornerRadius(Constants.cornerRadiusLarge)
                }
                .disabled(isSaveDisabled)
                .accessibilityIdentifier("mvp_keyboard_save_weight_bar_button")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.appCard)
        }
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add weight")
                .font(.title3.weight(.semibold))
                .foregroundColor(.appText)

            Picker("Units", selection: $measurementSystem) {
                Text("lb").tag(MeasurementSystem.imperial.rawValue)
                Text("kg").tag(MeasurementSystem.metric.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mvp_weight_unit_picker")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("0.0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(.appText)
                    .focused($isWeightFieldFocused)
                    .accessibilityIdentifier("mvp_weight_text_field")

                Text(currentSystem.weightUnit)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.appBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                    .stroke(isWeightFieldFocused ? Color.appPrimary : Color.appBorder, lineWidth: 1)
            )
            .cornerRadius(Constants.cornerRadiusLarge)

            if let weightValidationMessage {
                Label(weightValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.orange)
                    .accessibilityIdentifier("mvp_weight_validation_message")
            }

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.green)
                    .accessibilityIdentifier("mvp_weight_saved_message")
            }

            saveWeightButton
        }
        .padding(20)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(Constants.cornerRadiusLarge)
    }

    private var saveWeightButton: some View {
        Button(action: saveWeight) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                }

                Text(isSaving ? "Saving" : "Save weight")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundColor(.black)
            .background(isSaveDisabled ? Color.appBorder : Color.appPrimary)
            .cornerRadius(Constants.cornerRadiusLarge)
        }
        .disabled(isSaveDisabled)
        .accessibilityIdentifier("mvp_save_weight_button")
        .accessibilityHint(saveButtonAccessibilityHint)
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent entries")
                .font(.title3.weight(.semibold))
                .foregroundColor(.appText)

            HStack {
                Text("\(recentMetrics.count) saved")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                exportControl
            }

            if recentMetrics.isEmpty && !isLoading {
                Text("Saved weights will appear here.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.appCard)
                    .cornerRadius(Constants.cornerRadiusLarge)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentMetrics.prefix(10)) { metric in
                        recentMetricRow(metric)

                        if metric.id != recentMetrics.prefix(10).last?.id {
                            Divider()
                                .background(Color.appBorder)
                        }
                    }
                }
                .background(Color.appCard)
                .cornerRadius(Constants.cornerRadiusLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var exportControl: some View {
        if let exportFileURL {
            ShareLink(item: exportFileURL) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .disabled(recentMetrics.isEmpty)
        } else {
            Button(action: prepareCSVExport) {
                Label("CSV", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
            }
            .disabled(recentMetrics.isEmpty)
        }
    }

    private func recentMetricRow(_ metric: BodyMetrics) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appText)

                Text(metric.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            if let weight = metric.weight {
                let display = displayWeight(weight)
                Text("\(display.value) \(display.unit)")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.appText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var syncStatusText: String {
        PaidWeightLoggerMVPPolicy.syncStatusText(
            status: realtimeSyncManager.syncStatus,
            pendingCount: realtimeSyncManager.pendingSyncCount
        )
    }

    private var syncStatusColor: Color {
        switch realtimeSyncManager.syncStatus {
        case .success:
            return .green
        case .syncing:
            return .appPrimary
        case .error:
            return .orange
        case .offline:
            return .gray
        case .idle:
            return realtimeSyncManager.pendingSyncCount > 0 ? .orange : .green
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private var saveButtonAccessibilityHint: String {
        if isSaving {
            return "Saving your weight."
        }

        if weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a weight before saving."
        }

        if let weightValidationMessage {
            return weightValidationMessage
        }

        return "Saves this weight locally and queues account sync."
    }

    private func displayWeight(_ weightKg: Double) -> (value: String, unit: String) {
        let useMetric = currentSystem == .metric
        let value = UnitConversion.displayWeight(weightKg, useMetric: useMetric)
        return (String(format: "%.1f", value), currentSystem.weightUnit)
    }

    private func saveWeight() {
        guard !isSaveDisabled else { return }

        Task {
            await saveWeightEntry()
        }
    }

    @MainActor
    private func saveWeightEntry() async {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "Sign in again before logging weight."
            return
        }

        isSaving = true
        savedMessage = nil

        do {
            let validatedWeight = try ValidationService.shared.validateWeight(
                weightText,
                unit: currentSystem.weightUnit
            )
            let weightInKilograms = currentSystem == .imperial ? validatedWeight.lbsToKg : validatedWeight
            let now = Date()

            let metrics = BodyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: now,
                localDate: BodyMetricLocalDate.key(for: now),
                weight: weightInKilograms,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: now,
                updatedAt: now
            )

            try await CoreDataManager.shared.saveBodyMetricsAndWait(metrics, userId: userId, markAsSynced: false)
            realtimeSyncManager.updatePendingSyncCount()
            realtimeSyncManager.syncIfNeeded()
            AppServicePorts.analyticsTracker.track(event: "mvp_weight_logged")

            isWeightFieldFocused = false
            weightText = ""
            savedMessage = PaidWeightLoggerMVPPolicy.savedConfirmationText(isOnline: realtimeSyncManager.isOnline)
            exportFileURL = nil

            try? await Task.sleep(nanoseconds: 150_000_000)
            await loadRecentMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    @MainActor
    private func loadRecentMetrics() async {
        guard let userId = authManager.currentUser?.id else {
            recentMetrics = []
            isLoading = false
            return
        }

        isLoading = true
        let cachedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        recentMetrics = cachedMetrics
            .compactMap { $0.toBodyMetrics() }
            .filter { $0.weight != nil }
            .sorted { $0.date > $1.date }
        exportFileURL = nil
        if savedMessage == "CSV ready" {
            savedMessage = nil
        }
        isLoading = false
    }

    private func prepareCSVExport() {
        do {
            exportFileURL = try writeWeightCSV(metrics: recentMetrics)
            savedMessage = "CSV ready"
        } catch {
            errorMessage = "Could not prepare CSV export."
        }
    }

    private func writeWeightCSV(metrics: [BodyMetrics]) throws -> URL {
        var csv = "Date,Weight,Unit\n"
        let formatter = ISO8601DateFormatter()

        for metric in metrics.sorted(by: { $0.date < $1.date }) {
            guard let weight = metric.weight else { continue }
            let display = displayWeight(weight)
            csv += "\(formatter.string(from: metric.date)),\(display.value),\(display.unit)\n"
        }

        let fileName = "LogYourBody_weight_log_\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

#Preview {
    NavigationStack {
        MainTabView()
            .environmentObject(AuthManager())
            .environmentObject(RealtimeSyncManager.shared)
    }
}

private struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
}

private enum ChatDestination: Hashable {
    case timeline
    case settings
}

private struct ChatFirstRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [ChatDestination] = []
    @State private var isSidebarPresented = false
    @State private var draft = ""
    @State private var isResponding = false
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "I’m here to help you read your body data. Ask about your Body Score, metrics, or progress photos."
        )
    ]
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .leading) {
                chatSurface

                if isSidebarPresented {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isSidebarPresented = false
                            }
                        }

                    chatSidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .background(theme.colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ChatDestination.self) { destination in
                switch destination {
                case .timeline:
                    DashboardViewLiquid(layoutMode: .photoTimelineHUD)
                        .toolbar(.hidden, for: .tabBar)
                case .settings:
                    PreferencesView()
                        .environmentObject(authManager)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onEnded(handleSidebarGesture)
            )
            .accessibilityIdentifier("chat_first_root")
        }
    }

    private var chatSurface: some View {
        VStack(spacing: 0) {
            chatMessages
            starterPrompts
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            chatHeader
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    isSidebarPresented = true
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open sidebar")
            .accessibilityHint("Shows Timeline, Settings, and profile controls")
            .accessibilityIdentifier("chat_sidebar_button")

            VStack(alignment: .leading, spacing: 2) {
                Text("LogYourBody")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.text)

                Text("Body insights")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(theme.colors.accentTeal)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.55))
                .frame(height: 1)
        }
        .accessibilityIdentifier("chat_header")
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isResponding {
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(theme.colors.textSecondary)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .background(theme.colors.surface, in: Capsule())
                        .accessibilityLabel("Thinking")
                        .accessibilityIdentifier("chat_thinking_indicator")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: isResponding) { _, responding in
                guard responding else { return }
                if let lastID = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .accessibilityIdentifier("chat_messages")
    }

    private var starterPrompts: some View {
        Group {
            if messages.count == 1 && !isComposerFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        starterPrompt("How am I doing?")
                        starterPrompt("Open my Timeline")
                        starterPrompt("What is Body Score?")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .transition(.opacity)
                .accessibilityIdentifier("chat_starter_prompts")
            }
        }
    }

    private func starterPrompt(_ text: String) -> some View {
        Button(text) {
            send(text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.colors.text)
        .padding(.horizontal, 13)
        .frame(minHeight: 38)
        .background(theme.colors.surface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.colors.border, lineWidth: 1)
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message LogYourBody", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.text)
                .tint(theme.colors.primary)
                .submitLabel(.send)
                .onSubmit {
                    send(draft)
                }
                .accessibilityIdentifier("chat_composer")

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? theme.colors.background : theme.colors.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(canSend ? theme.colors.text : theme.colors.surface, in: Circle())
            }
            .disabled(!canSend || isResponding)
            .buttonStyle(.plain)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("chat_send_button")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.55))
                .frame(height: 1)
        }
        .animation(.easeOut(duration: 0.18), value: canSend)
    }

    private var chatSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("LogYourBody")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.colors.text)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isSidebarPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close sidebar")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)

            Text("Workspace")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.colors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.bottom, 7)

            sidebarButton(title: "Chat", icon: "bubble.left.and.bubble.right.fill") {
                closeSidebar()
            }

            sidebarButton(title: "Timeline", icon: "photo.on.rectangle.angled") {
                closeSidebar()
                path.append(.timeline)
            }
            .accessibilityIdentifier("chat_timeline_link")

            sidebarButton(title: "Settings", icon: "gearshape.fill") {
                closeSidebar()
                path.append(.settings)
            }
            .accessibilityIdentifier("chat_settings_link")

            Spacer(minLength: 0)

            Text("Your data stays in the existing LogYourBody sync and profile flows.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: 306, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.7))
                .frame(width: 1)
        }
        .accessibilityIdentifier("chat_sidebar")
    }

    private func sidebarButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func closeSidebar() {
        withAnimation(.easeOut(duration: 0.22)) {
            isSidebarPresented = false
        }
    }

    private func handleSidebarGesture(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        guard abs(horizontalDistance) > 60 else { return }

        if isSidebarPresented {
            if horizontalDistance < 0 {
                closeSidebar()
            }
        } else {
            // Support the existing left-swipe muscle memory while also
            // accepting the conventional leading-edge reveal gesture.
            withAnimation(.easeOut(duration: 0.22)) {
                isSidebarPresented = true
            }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        draft = ""
        isComposerFocused = false
        isResponding = true
        AppServicePorts.analyticsTracker.track(event: "chat_first_message_sent")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            messages.append(ChatMessage(role: .assistant, text: response(for: trimmed)))
            isResponding = false
        }
    }

    private func response(for text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("how") || normalized.contains("score") || normalized.contains("doing") {
            if let score = BodyScoreCache.shared.latestResult(for: authManager.currentUser?.id)?.score {
                return "Your latest Body Score is \(score). Open Timeline from the sidebar to see the selected day, essential metrics, and your photo history together."
            }
            return "Open Timeline from the sidebar to see your current Body Score and the measurements behind it."
        }

        if normalized.contains("timeline") || normalized.contains("photo") {
            return "Timeline is the clearest place to read change over time. Use the photo strip to move day by day, then tap a metric for detail."
        }

        if normalized.contains("height") || normalized.contains("profile") {
            return "Open Settings from the sidebar, choose Profile, then tap Height. The field editor opens directly."
        }

        return "I can help you read your Body Score, metrics, and progress photos. Try asking how you’re doing or open Timeline."
    }
}

private struct ChatBubble: View {
    @Environment(\.theme) private var theme
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 36)
            }

            Text(message.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(message.role == .user ? theme.colors.background : theme.colors.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    message.role == .user
                        ? theme.colors.text
                        : theme.colors.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    if message.role == .assistant {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.colors.border, lineWidth: 1)
                    }
                }

            if message.role == .assistant {
                Spacer(minLength: 36)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You: (message.text)" : "LogYourBody: (message.text)")
    }
}
