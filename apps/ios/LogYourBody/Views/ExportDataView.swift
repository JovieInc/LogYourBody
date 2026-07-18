//
// ExportDataView.swift
// LogYourBody
//
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ExportDataView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) private var openURL
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedFormats: Set<ExportFormat> = [.json]
    @State private var includePhotos = false
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var exportMethod: ExportMethod = .email

    enum ExportMethod: String, CaseIterable {
        case email = "Email Link"
        case download = "Direct Download"

        var description: String {
            switch self {
            case .email:
                return "Receive a secure JSON download link at your registered email address."
            case .download:
                return "Save one JSON file directly to this device."
            }
        }
    }

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }
    }

    private var isDirectDownloadSupported: Bool {
        exportMethod != .download || (selectedFormats == [.json] && !includePhotos)
    }

    private var isExportDisabled: Bool {
        isExporting || (exportMethod == .download && (selectedFormats.isEmpty || !isDirectDownloadSupported))
    }

    var body: some View {
        ZStack {
            Color.jovieCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    exportHeader
                    deliveryMethodPicker
                    deliveryDetails
                    includedData
                    privacyAndSupport
                }
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, JovieTokens.sectionGap)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if isExporting {
                exportProgressOverlay
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            exportAction
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityLabel("Cancel export")
            }
        }
        .alert("Export failed", isPresented: $showError) {
            Button("Try Again") {
                exportData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Export ready", isPresented: $showSuccess) {
            Button("Done", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
        }
        .onChange(of: exportMethod) { _, method in
            if method == .download {
                selectedFormats = [.json]
                includePhotos = false
            }
        }
        .onChange(of: showError) { _, isShowing in
            if isShowing {
                UIAccessibility.post(notification: .announcement, argument: errorMessage)
            }
        }
    }

    private var exportHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your data, on your terms", systemImage: "lock.document.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.jovieTextSecondary)

            Text("Export your data")
                .font(.title2.weight(.bold))
                .foregroundColor(.jovieText)

            Text("Create a portable copy of your LogYourBody records.")
                .font(.body)
                .foregroundColor(.jovieTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var deliveryMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delivery")
                .font(.headline)
                .foregroundColor(.jovieText)

            Picker("Delivery method", selection: $exportMethod) {
                ForEach(ExportMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                    .fill(Color.jovieSurface)
            )
            .accessibilityIdentifier("export_delivery_method_picker")
        }
    }

    private var deliveryDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exportMethod == .email ? "Secure email link" : "Direct device download")
                .font(.headline)
                .foregroundColor(.jovieText)

            Text(exportMethod.description)
                .font(.subheadline)
                .foregroundColor(.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if exportMethod == .download {
                Label("Direct download contains one JSON file and does not include progress photos.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundColor(.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.cardRadius,
            tint: .jovieText,
            tintOpacity: 0.045,
            borderColor: .jovieHairline,
            borderOpacity: 0.9
        )
        .accessibilityElement(children: .combine)
    }

    private var includedData: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Included")
                .font(.headline)
                .foregroundColor(.jovieText)

            VStack(alignment: .leading, spacing: 4) {
                DataTypeRow(
                    icon: "person.fill",
                    title: "Profile information",
                    description: "Name, email, date of birth, and height"
                )
                DataTypeRow(
                    icon: "scalemass",
                    title: "Body metrics",
                    description: "Weight, body fat, and measurements"
                )
                DataTypeRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Progress history",
                    description: "Historical data points and daily logs"
                )
            }
            .padding(12)
            .systemBGlassSurface(
                cornerRadius: JovieTokens.cardRadius,
                tint: .jovieText,
                tintOpacity: 0.045,
                borderColor: .jovieHairline,
                borderOpacity: 0.9
            )
        }
    }

    private var privacyAndSupport: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                exportMethod == .email
                    ? "A secure download link will be sent to your registered email address and expires after 24 hours."
                    : "The JSON file is saved to your device. Share it only with people and services you trust."
            )
            .font(.footnote)
            .foregroundColor(.jovieTextSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Email support about an export") {
                requestExportViaEmail()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.jovieText)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .accessibilityHint("Opens an email to LogYourBody support.")
        }
    }

    private var exportAction: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.jovieHairline)
                .frame(height: 1)

            BaseButton(
                exportMethod == .email ? "Email secure link" : "Download JSON",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    isLoading: isExporting,
                    isEnabled: !isExportDisabled,
                    fullWidth: true,
                    icon: "square.and.arrow.up",
                    cornerRadius: JovieTokens.controlRadius
                ),
                action: exportData
            )
            .accessibilityIdentifier("export_data_action")
            .accessibilityHint(
                exportMethod == .email
                    ? "Sends a secure export link to your registered email address."
                    : "Prepares a JSON export on this device."
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.vertical, 12)
        }
        .background(Color.jovieCanvas.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .jovieText))
                    .scaleEffect(1.2)

                Text("Preparing your data")
                    .font(.headline)
                    .foregroundColor(.jovieText)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                    .fill(Color.jovieSurfaceElevated)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing your data")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Export Functionality

    private func exportData() {
        Task {
            await performExport()
        }
    }

    private func requestExportViaEmail() {
        let recipient = ProductRegistry.supportEmail
        let subject = "LogYourBody Data Export Request"
        let body = """
        Hello LogYourBody Support,

        I would like to request an export of my LogYourBody account data associated with this email address.

        Thank you,
        """

        let allowed = CharacterSet.urlQueryAllowed

        guard
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
            let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
        else {
            return
        }

        openURL(url)
    }

    @MainActor
    private func performExport() async {
        isExporting = true

        if exportMethod == .email {
            // Use edge function for email export
            await performEmailExport()
        } else {
            // Use local export for direct download
            await performLocalExport()
        }
    }

    @MainActor
    private func performEmailExport() async {
        do {
            guard let token = await authManager.getAccessToken() else {
                throw ExportError.exportFailed("Authentication failed")
            }

            // Call edge function
            guard let url = try? SupabaseURLBuilder.functionURL("export-user-data") else {
                throw ExportError.exportFailed("Invalid server configuration")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["format": "json", "emailLink": true] as [String: Any]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ExportError.exportFailed("Server error")
            }

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                successMessage = message
            } else {
                successMessage = "Export link has been sent to your email. The link will expire in 24 hours."
            }

            // Small delay for visual feedback
            try await Task.sleep(nanoseconds: 500_000_000)

            isExporting = false
            showSuccess = true
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func performLocalExport() async {
        do {
            guard isDirectDownloadSupported else {
                throw ExportError.unsupportedDirectDownload
            }

            // Get all user data
            guard let user = authManager.currentUser else {
                throw ExportError.noUserData
            }

            // Fetch all data from Core Data
            let bodyMetrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: user.id)
            let dailyLogs = await CoreDataManager.shared.fetchAllDailyLogs(for: user.id)

            // Create export data structure
            let exportData = ExportData(
                exportDate: Date(),
                user: user,
                bodyMetrics: bodyMetrics,
                dailyLogs: dailyLogs,
                photoURLs: includePhotos ? extractPhotoURLs(from: bodyMetrics) : []
            )

            // Create temporary directory
            let tempDir = FileManager.default.temporaryDirectory
            let exportDir = tempDir.appendingPathComponent("LogYourBody_Export_\(Date().timeIntervalSince1970)")
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

            // Export files based on selected formats
            var exportedFiles: [URL] = []

            for format in selectedFormats {
                switch format {
                case .json:
                    let jsonURL = try exportAsJSON(exportData, to: exportDir)
                    exportedFiles.append(jsonURL)
                case .csv:
                    let csvURLs = try exportAsCSV(exportData, to: exportDir)
                    exportedFiles.append(contentsOf: csvURLs)
                }
            }

            // Download photos if requested
            if includePhotos && !exportData.photoURLs.isEmpty {
                let photosDir = exportDir.appendingPathComponent("photos")
                try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

                // Note: In a real implementation, you would download the photos here
                // For now, we'll just create a manifest
                let photoManifest = exportData.photoURLs.joined(separator: "\n")
                let manifestURL = photosDir.appendingPathComponent("photo_urls.txt")
                try photoManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
                exportedFiles.append(manifestURL)
            }

            guard exportedFiles.count == 1, let finalExportURL = exportedFiles.first else {
                throw ExportError.unsupportedDirectDownload
            }

            // Show share sheet
            exportedFileURL = finalExportURL

            // Small delay for visual feedback
            try await Task.sleep(nanoseconds: 500_000_000)

            isExporting = false
            showShareSheet = true
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func exportAsJSON(_ data: ExportData, to directory: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(data)
        let fileName = "LogYourBody_Export_\(formatDate(Date())).json"
        let fileURL = directory.appendingPathComponent(fileName)

        try jsonData.write(to: fileURL)
        return fileURL
    }

    private func exportAsCSV(_ data: ExportData, to directory: URL) throws -> [URL] {
        var urls: [URL] = []

        // Export body metrics as CSV
        let metricsCSV = createBodyMetricsCSV(from: data.bodyMetrics)
        let metricsFileName = "body_metrics_\(formatDate(Date())).csv"
        let metricsURL = directory.appendingPathComponent(metricsFileName)
        try metricsCSV.write(to: metricsURL, atomically: true, encoding: .utf8)
        urls.append(metricsURL)

        // Export daily logs as CSV
        if !data.dailyLogs.isEmpty {
            let logsCSV = createDailyLogsCSV(from: data.dailyLogs)
            let logsFileName = "daily_logs_\(formatDate(Date())).csv"
            let logsURL = directory.appendingPathComponent(logsFileName)
            try logsCSV.write(to: logsURL, atomically: true, encoding: .utf8)
            urls.append(logsURL)
        }

        return urls
    }

    private func createBodyMetricsCSV(from metrics: [BodyMetrics]) -> String {
        var csv = "Date,Weight,Weight Unit,Body Fat %,FFMI,Muscle Mass,Bone Mass,Notes,Photo URL\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        let heightCm = authManager.currentUser?.profile?.height
        let heightInches: Double?
        if let heightCm, heightCm > 0 {
            heightInches = heightCm / 2.54
        } else {
            heightInches = nil
        }

        let sortedMetrics = metrics.sorted { $0.date < $1.date }

        for metric in sortedMetrics {
            let date = dateFormatter.string(from: metric.date)
            let weight = metric.weight ?? 0
            let weightUnit = metric.weightUnit ?? "lbs"
            let bodyFat = metric.bodyFatPercentage ?? 0
            let ffmiValue: Double
            if let heightInches,
               let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                   for: metric.date,
                   metrics: sortedMetrics,
                   heightInches: heightInches
               ) {
                ffmiValue = ffmiResult.value
            } else {
                ffmiValue = 0
            }
            let muscleMass = metric.muscleMass ?? 0
            let boneMass = metric.boneMass ?? 0
            let notes = metric.notes ?? ""
            let photoURL = metric.photoUrl ?? ""

            csv += "\(date),\(weight),\(weightUnit),\(bodyFat),\(ffmiValue),\(muscleMass),\(boneMass),\"\(notes)\",\(photoURL)\n"
        }

        return csv
    }

    private func createDailyLogsCSV(from logs: [DailyLog]) -> String {
        var csv = "Date,Weight,Weight Unit,Steps,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        for log in logs.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: log.date)
            let weight = log.weight ?? 0
            let weightUnit = log.weightUnit ?? ""
            let steps = log.stepCount ?? 0
            let notes = log.notes ?? ""

            csv += "\(date),\(weight),\(weightUnit),\(steps),\"\(notes)\"\n"
        }

        return csv
    }

    private func extractPhotoURLs(from metrics: [BodyMetrics]) -> [String] {
        return metrics.compactMap { $0.photoUrl }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct ExportData: Codable {
    let exportDate: Date
    let user: User
    let bodyMetrics: [BodyMetrics]
    let dailyLogs: [DailyLog]
    let photoURLs: [String]
}

enum ExportError: LocalizedError {
    case noUserData
    case exportFailed(String)
    case unsupportedDirectDownload

    var errorDescription: String? {
        switch self {
        case .noUserData:
            return "No user data found to export"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .unsupportedDirectDownload:
            return "Direct download supports one JSON file without progress photos. Contact support for other export requests."
        }
    }
}

// MARK: - Helper Views

private struct DataTypeRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundColor(.jovieTextSecondary)
                .frame(width: JovieTokens.minimumHitTarget)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.jovieText)

                Text(description)
                    .font(.footnote)
                    .foregroundColor(.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .frame(minHeight: JovieTokens.minimumHitTarget)
        .accessibilityElement(children: .combine)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportDataView()
        .environmentObject(AuthManager.shared)
}
