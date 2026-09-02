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
    @Binding private var releaseReviewDestination: ReleaseReviewDestination?

    init(releaseReviewDestination: Binding<ReleaseReviewDestination?> = .constant(nil)) {
        _releaseReviewDestination = releaseReviewDestination
    }

    var body: some View {
        NavigationStack {
            switch selectedSurface {
            case .photoTimelineHUD:
                DashboardViewLiquid(
                    layoutMode: .photoTimelineHUD,
                    releaseReviewDestination: $releaseReviewDestination
                )
            case .legacyFullDashboardBeta:
                DashboardViewLiquid(
                    layoutMode: .legacyTabbed,
                    releaseReviewDestination: $releaseReviewDestination
                )
            case .weightLoggerMVP:
                PaidWeightLoggerMVPView()
            }
        }
        .onAppear {
            updateSelectedSurface()
        }
        .onChange(of: releaseReviewDestination) { _, destination in
            if destination == .timeline {
                selectedSurface = .photoTimelineHUD
            }
        }
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
    enum Role: Equatable {
        case assistant
        case user
    }

    enum Delivery: Equatable {
        case complete
        case sending
        case failed
        case stopped
    }

    var id: String
    let role: Role
    var text: String
    let clientMessageId: String?
    let replyToClientMessageId: String?
    var delivery: Delivery

    static let welcome = ChatMessage(
        id: "chat-welcome",
        role: .assistant,
        text: "Ask about your measurements, trends, or progress photos. " +
            "I’ll use only the body context authorized for your account.",
        clientMessageId: nil,
        replyToClientMessageId: nil,
        delivery: .complete
    )

    init(
        id: String = UUID().uuidString,
        role: Role,
        text: String,
        clientMessageId: String? = nil,
        replyToClientMessageId: String? = nil,
        delivery: Delivery = .complete
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.clientMessageId = clientMessageId
        self.replyToClientMessageId = replyToClientMessageId
        self.delivery = delivery
    }
}

private struct FailedChatTurn: Equatable {
    let message: String
    let clientMessageId: String
}

@MainActor
struct ChatTabView: View {
    var showsTranscript: Bool = true
    var onExpandRequest: () -> Void = {}

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var composerTextHeight: CGFloat = 0
    @State private var isResponding = false
    @State private var isLoadingConversation = true
    @State private var messages: [ChatMessage] = [.welcome]
    @State private var conversationId = UUID().uuidString
    @State private var currentRequestTask: Task<Void, Never>?
    @State private var activeClientMessageId: String?
    @State private var requestGeneration: UUID?
    @State private var failedTurn: FailedChatTurn?
    @State private var chatErrorMessage: String?
    @State private var isConversationLoadRetryAvailable = false
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            accessibilityMarker(
                id: showsTranscript ? "chat_tab_root" : "home_chat_composer_dock",
                label: showsTranscript ? "Chat" : "Chat composer"
            )
            chatSurface
        }
        .background {
            if showsTranscript {
                theme.colors.background.ignoresSafeArea()
            }
        }
        .modifier(ChatTabWorldClassScreenModifier(isEnabled: showsTranscript))
        .task(id: authManager.currentUser?.id) {
            await loadLatestConversation()
        }
        .onDisappear {
            currentRequestTask?.cancel()
        }
        .alert("Delete this chat?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentConversation()
            }
        } message: {
            Text("This permanently removes the conversation from LogYourBody.")
        }
    }

    private var chatSurface: some View {
        VStack(spacing: 0) {
            if showsTranscript {
                chatMessages
            }
            starterPrompts
        }
        .frame(maxHeight: showsTranscript ? .infinity : nil)
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsTranscript {
                chatHeader
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Text("Private body chat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)

            if isLoadingConversation {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.textSecondary)
                    .accessibilityLabel("Loading conversation")
            } else {
                Circle()
                    .fill(chatErrorMessage == nil ? theme.colors.accentTeal : Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            if messages.contains(where: { $0.role == .user }) {
                Menu {
                    Button("Delete Chat", systemImage: "trash", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Chat options")
                .accessibilityIdentifier("chat_options_menu")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.55))
                .frame(height: 1)
        }
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if isLoadingConversation {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.colors.textSecondary)

                            Text("Loading your conversation")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("chat_loading_state")
                    }

                    ForEach(messages) { message in
                        if !message.text.isEmpty {
                            ChatBubble(message: message)
                                .id(message.id)
                        }
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
        VStack(spacing: 0) {
            if let chatErrorMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.orange)

                    Text(chatErrorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if failedTurn != nil {
                        Button("Retry", action: retryFailedTurn)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.text)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat_retry_button")
                    } else if isConversationLoadRetryAvailable {
                        Button("Retry") {
                            Task { await loadLatestConversation() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.text)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat_reload_button")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(theme.colors.surface.opacity(0.92))
                .accessibilityElement(children: .contain)
            }

            if messages == [.welcome] && !isComposerFocused && !isLoadingConversation {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        starterPrompt("How am I doing?")
                        starterPrompt("Summarize my trend")
                        starterPrompt("What changed recently?")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .transition(.opacity)
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
        let isMultiline = ChatComposerGeometry.isMultiline(textHeight: composerTextHeight)
        let cornerRadius = ChatComposerGeometry.cornerRadius(isMultiline: isMultiline)

        return HStack(alignment: .bottom, spacing: JovieTokens.itemGap) {
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
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChatComposerTextHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }

            Button {
                if isResponding {
                    stopResponse()
                } else {
                    send(draft)
                }
            } label: {
                Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: isResponding ? 11 : 15, weight: .bold))
                    .foregroundStyle(
                        (canSend || isResponding) ? theme.colors.background : theme.colors.textTertiary
                    )
                    .frame(
                        width: JovieTokens.minimumHitTarget,
                        height: JovieTokens.minimumHitTarget
                    )
                    .background(
                        (canSend || isResponding) ? theme.colors.text : theme.colors.surface,
                        in: Circle()
                    )
            }
            .disabled((!canSend && !isResponding) || isLoadingConversation)
            .buttonStyle(.plain)
            .accessibilityLabel(isResponding ? "Stop answer" : "Send message")
            .accessibilityIdentifier("chat_send_button")
        }
        .padding(.leading, JovieTokens.compactInset)
        .padding(.trailing, JovieTokens.tightGap)
        .padding(.vertical, JovieTokens.tightGap)
        .dashboardChromeGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            cornerRadius: cornerRadius,
            tint: isComposerFocused ? theme.colors.primary : .white,
            tintOpacity: isComposerFocused ? 0.16 : 0.1
        )
        .background {
            Color.clear
                .accessibilityElement()
                .accessibilityLabel("Chat composer container")
                .accessibilityIdentifier("chat_composer_shell")
        }
        .padding(.horizontal, JovieTokens.screenInset)
        .padding(.vertical, JovieTokens.itemGap)
        .onPreferenceChange(ChatComposerTextHeightPreferenceKey.self) { height in
            composerTextHeight = height
        }
        .animation(
            ChatComposerGeometry.transitionAnimation(reduceMotion: reduceMotion),
            value: isMultiline
        )
        .animation(
            ChatComposerGeometry.transitionAnimation(reduceMotion: reduceMotion),
            value: canSend
        )
    }

    private func accessibilityMarker(id: String, label: String) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoadingConversation &&
            !isResponding
    }

    private var chatService: ChatServicing {
        AppServicePorts.chatService
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding, !isLoadingConversation else { return }

        let clientMessageId = UUID().uuidString
        messages.append(
            ChatMessage(
                role: .user,
                text: trimmed,
                clientMessageId: clientMessageId,
                delivery: .sending
            )
        )
        draft = ""
        isComposerFocused = false
        if HomeChatChromePolicy.shouldExpandChat(afterSendingUserMessage: true) {
            onExpandRequest()
        }
        startTurn(message: trimmed, clientMessageId: clientMessageId)
    }

    private func startTurn(message: String, clientMessageId: String) {
        currentRequestTask?.cancel()
        messages.removeAll { $0.replyToClientMessageId == clientMessageId }
        if let userIndex = messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
            messages[userIndex].delivery = .sending
        }
        messages.append(
            ChatMessage(
                id: "stream-\(clientMessageId)",
                role: .assistant,
                text: "",
                replyToClientMessageId: clientMessageId,
                delivery: .sending
            )
        )

        failedTurn = nil
        chatErrorMessage = nil
        isConversationLoadRetryAvailable = false
        isResponding = true
        activeClientMessageId = clientMessageId
        let generation = UUID()
        requestGeneration = generation
        AppServicePorts.analyticsTracker.track(event: "chat_first_message_sent")

        currentRequestTask = Task { @MainActor in
            defer {
                if requestGeneration == generation {
                    isResponding = false
                    activeClientMessageId = nil
                    requestGeneration = nil
                    currentRequestTask = nil
                }
            }

            guard let accessToken = await chatAccessToken() else {
                applyTurnFailure(
                    ChatServiceError.authenticationExpired,
                    message: message,
                    clientMessageId: clientMessageId
                )
                return
            }

            do {
                var completed = false
                let stream = chatService.streamMessage(
                    accessToken: accessToken,
                    conversationId: conversationId,
                    clientMessageId: clientMessageId,
                    message: message
                )

                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .metadata(let serverConversationId, _, _):
                        conversationId = serverConversationId
                    case .delta(let text):
                        mutateAssistant(clientMessageId: clientMessageId) { assistant in
                            assistant.text += text
                        }
                    case .completed(let messageId, _, _):
                        mutateAssistant(clientMessageId: clientMessageId) { assistant in
                            assistant.id = messageId
                            assistant.delivery = .complete
                        }
                        if let userIndex = messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                            messages[userIndex].delivery = .complete
                        }
                        completed = true
                    case .failure(_, let message, let retryable):
                        throw ChatServiceError.server(message: message, retryable: retryable)
                    }
                }

                try Task.checkCancellation()
                guard completed else { throw ChatServiceError.invalidResponse }
                AppServicePorts.analyticsTracker.track(event: "chat_first_answer_completed")
            } catch is CancellationError {
                return
            } catch let error as ChatServiceError {
                applyTurnFailure(error, message: message, clientMessageId: clientMessageId)
            } catch {
                applyTurnFailure(
                    ChatServiceError.server(
                        message: "Chat is temporarily unavailable. Please try again.",
                        retryable: true
                    ),
                    message: message,
                    clientMessageId: clientMessageId
                )
            }
        }
    }

    private func retryFailedTurn() {
        guard let failedTurn, !isResponding else { return }
        startTurn(message: failedTurn.message, clientMessageId: failedTurn.clientMessageId)
    }

    private func stopResponse() {
        guard isResponding,
              let clientMessageId = activeClientMessageId,
              let userIndex = messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) else {
            isResponding = false
            return
        }

        let failedMessage = messages[userIndex].text
        let task = currentRequestTask
        requestGeneration = nil
        currentRequestTask = nil
        task?.cancel()

        mutateAssistant(clientMessageId: clientMessageId) { assistant in
            assistant.delivery = .stopped
        }
        messages[userIndex].delivery = .stopped
        failedTurn = FailedChatTurn(message: failedMessage, clientMessageId: clientMessageId)
        chatErrorMessage = "Answer stopped. Retry when you’re ready."
        isResponding = false
        activeClientMessageId = nil
        AppServicePorts.analyticsTracker.track(event: "chat_first_answer_cancelled")
    }

    private func mutateAssistant(
        clientMessageId: String,
        mutation: (inout ChatMessage) -> Void
    ) {
        guard let index = messages.firstIndex(where: {
            $0.replyToClientMessageId == clientMessageId
        }) else { return }
        mutation(&messages[index])
    }

    private func applyTurnFailure(
        _ error: ChatServiceError,
        message: String,
        clientMessageId: String
    ) {
        if let assistantIndex = messages.firstIndex(where: {
            $0.replyToClientMessageId == clientMessageId
        }) {
            if messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            } else {
                messages[assistantIndex].delivery = .failed
            }
        }
        if let userIndex = messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
            messages[userIndex].delivery = .failed
        }
        if error != .authenticationExpired && error.isRetryable {
            failedTurn = FailedChatTurn(message: message, clientMessageId: clientMessageId)
        } else {
            failedTurn = nil
        }
        isConversationLoadRetryAvailable = false
        chatErrorMessage = error.localizedDescription
        AppServicePorts.analyticsTracker.track(
            event: "chat_first_answer_failed",
            properties: ["retryable": error.isRetryable ? "true" : "false"]
        )
    }

    private func loadLatestConversation() async {
        currentRequestTask?.cancel()
        isLoadingConversation = true
        isConversationLoadRetryAvailable = false
        defer { isLoadingConversation = false }

        guard authManager.currentUser != nil,
              let accessToken = await chatAccessToken() else {
            chatErrorMessage = ChatServiceError.authenticationExpired.localizedDescription
            return
        }

        do {
            guard let conversation = try await chatService.loadLatest(accessToken: accessToken) else {
                messages = [.welcome]
                conversationId = UUID().uuidString
                return
            }
            conversationId = conversation.id
            messages = conversation.messages.map { message in
                ChatMessage(
                    id: message.id,
                    role: message.role == .user ? .user : .assistant,
                    text: message.content,
                    clientMessageId: message.clientMessageId,
                    delivery: .complete
                )
            }
            if messages.isEmpty { messages = [.welcome] }
            chatErrorMessage = nil
        } catch let error as ChatServiceError {
            chatErrorMessage = error.localizedDescription
            isConversationLoadRetryAvailable = error.isRetryable
        } catch {
            chatErrorMessage = "Your conversation could not be loaded. Please try again."
            isConversationLoadRetryAvailable = true
        }
    }

    private func deleteCurrentConversation() {
        guard !isResponding else { return }

        Task { @MainActor in
            guard let accessToken = await chatAccessToken() else {
                chatErrorMessage = ChatServiceError.authenticationExpired.localizedDescription
                return
            }

            do {
                try await chatService.deleteConversation(
                    accessToken: accessToken,
                    conversationId: conversationId
                )
                messages = [.welcome]
                conversationId = UUID().uuidString
                failedTurn = nil
                chatErrorMessage = nil
                isConversationLoadRetryAvailable = false
                AppServicePorts.analyticsTracker.track(event: "chat_first_conversation_deleted")
            } catch let error as ChatServiceError {
                chatErrorMessage = error.localizedDescription
            } catch {
                chatErrorMessage = "The chat could not be deleted. Please try again."
            }
        }
    }

    private func chatAccessToken() async -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestChatFirstFixture") {
            return "ui-test-bearer-token"
        }
        #endif
        return await authManager.getAccessToken()
    }
}

private struct ChatComposerTextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatTabWorldClassScreenModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.worldClassScreen(.chat)
        } else {
            content
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.theme) private var theme
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
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
                    .opacity(message.delivery == .failed ? 0.72 : 1)

                if message.role == .assistant {
                    Spacer(minLength: 36)
                }
            }

            if message.delivery == .failed || message.delivery == .stopped {
                Text(message.delivery == .stopped ? "Stopped" : "Not delivered")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message.role == .user
                ? "You: \(message.text)"
                : "LogYourBody: \(message.text)"
        )
    }
}
