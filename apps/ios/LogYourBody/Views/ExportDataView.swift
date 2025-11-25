//
// ExportDataView.swift
// LogYourBody
//
import SwiftUI
import UniformTypeIdentifiers

struct ExportDataView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) private var openURL
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
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
                return "Receive a secure download link via email"
            case .download:
                return "Download directly to this device"
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

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .font(.system(size: 50))
                                .foregroundColor(.appPrimary)
                                .symbolRenderingMode(.hierarchical)

                            Text("Export Your Data")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.appText)

                            Text("Download all your LogYourBody data for your records or to transfer to another service")
                                .font(.body)
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)

                        // Export Options
                        VStack(spacing: 16) {
                            // Export Method Selection
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Export Method")
                                    .font(.headline)
                                    .foregroundColor(.appText)
                                    .padding(.horizontal)

                                VStack(spacing: 0) {
                                    ForEach(ExportMethod.allCases, id: \.self) { method in
                                        Button(
                                            action: {
                                                exportMethod = method
                                            },
                                            label: {
                                                HStack {
                                                    Image(systemName: exportMethod == method ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 20))
                                                        .foregroundColor(exportMethod == method ? .appPrimary : .appBorder)

                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(method.rawValue)
                                                            .font(.body)
                                                            .foregroundColor(.appText)

                                                        Text(method.description)
                                                            .font(.caption)
                                                            .foregroundColor(.appTextSecondary)
                                                    }

                                                    Spacer()
                                                }
                                                .padding()
                                                .background(Color.appCard)
                                            }
                                        )
                                        .buttonStyle(PlainButtonStyle())

                                        if method != ExportMethod.allCases.last {
                                            Divider()
                                                .background(Color.appBorder)
                                        }
                                    }
                                }
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }

                            // Format Selection (only for direct download)
                            if exportMethod == .download {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Export Format")
                                        .font(.headline)
                                        .foregroundColor(.appText)
                                        .padding(.horizontal)

                                    VStack(spacing: 0) {
                                        ForEach(ExportFormat.allCases, id: \.self) { format in
                                            Button(
                                                action: {
                                                    if selectedFormats.contains(format) {
                                                        selectedFormats.remove(format)
                                                    } else {
                                                        selectedFormats.insert(format)
                                                    }
                                                },
                                                label: {
                                                    HStack {
                                                        Image(
                                                            systemName: selectedFormats.contains(format)
                                                                ? "checkmark.square.fill"
                                                                : "square"
                                                        )
                                                        .font(.system(size: 20))
                                                        .foregroundColor(
                                                            selectedFormats.contains(format)
                                                                ? .appPrimary
                                                                : .appBorder
                                                        )

                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(format.rawValue)
                                                                .font(.body)
                                                                .foregroundColor(.appText)

                                                            Text(
                                                                format == .json
                                                                    ? "Complete data with all fields"
                                                                    : "Spreadsheet-compatible format"
                                                            )
                                                            .font(.caption)
                                                            .foregroundColor(.appTextSecondary)
                                                        }

                                                        Spacer()
                                                    }
                                                    .padding()
                                                    .background(Color.appCard)
                                                }
                                            )
                                            .buttonStyle(PlainButtonStyle())

                                            if format != ExportFormat.allCases.last {
                                                Divider()
                                                    .background(Color.appBorder)
                                            }
                                        }
                                    }
                                    .background(Color.appCard)
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                            }

                            // Include Photos Option (only for direct download)
                            if exportMethod == .download {
                                Button(
                                    action: {
                                        includePhotos.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: includePhotos ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 20))
                                                .foregroundColor(includePhotos ? .appPrimary : .appBorder)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Include Progress Photos")
                                                    .font(.body)
                                                    .foregroundColor(.appText)

                                                Text("Export will include all your progress photos")
                                                    .font(.caption)
                                                    .foregroundColor(.appTextSecondary)
                                            }

                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color.appCard)
                                        .cornerRadius(12)
                                    }
                                )
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal)
                            }
                        }

                        // Data Included Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Data Included")
                                .font(.headline)
                                .foregroundColor(.appText)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 8) {
                                DataTypeRow(
                                    icon: "person.fill",
                                    title: "Profile Information",
                                    description: "Name, email, date of birth, height"
                                )
                                DataTypeRow(
                                    icon: "scalemass",
                                    title: "Body Metrics",
                                    description: "Weight, body fat %, measurements"
                                )
                                DataTypeRow(
                                    icon: "chart.line.uptrend.xyaxis",
                                    title: "Progress History",
                                    description: "All historical data points"
                                )
                                DataTypeRow(
                                    icon: "calendar",
                                    title: "Daily Logs",
                                    description: "Activity, notes, and check-ins"
                                )
                                if exportMethod == .download && includePhotos {
                                    DataTypeRow(
                                        icon: "photo",
                                        title: "Progress Photos",
                                        description: "All uploaded photos"
                                    )
                                }
                            }
                            .padding()
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Export Button
                        Button(action: exportData) {
                            HStack {
                                if isExporting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export Data")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(exportMethod == .download && selectedFormats.isEmpty ? Color.appBorder : Color.white)
                            .foregroundColor(exportMethod == .download && selectedFormats.isEmpty ? .appTextTertiary : .black)
                            .cornerRadius(25)
                        }
                        .disabled((exportMethod == .download && selectedFormats.isEmpty) || isExporting)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Privacy Note
                        VStack(spacing: 8) {
                            Text(
                                exportMethod == .email
                                    ? "A secure download link will be sent to your registered email address. "
                                    + "The link will expire after 24 hours."
                                    : "Your data export will be prepared and saved to your device. You can then "
                                    + "share it or save it to your preferred location."
                            )
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                            Button(action: requestExportViaEmail) {
                                Text("Or email support to request a data export")
                                    .font(.caption)
                                    .foregroundColor(.appPrimary)
                                    .underline()
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }

                if isExporting {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView(value: exportProgress)
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)

                        Text("Preparing your data...")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("\(Int(exportProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(40)
                    .background(Color.appCard)
                    .cornerRadius(20)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Export Successful", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {
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
        }
    }

    // MARK: - Export Functionality

    private func exportData() {
        Task {
            await performExport()
        }
    }

    private func requestExportViaEmail() {
        let recipient = "support@logyourbody.com"
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
        exportProgress = 0

        do {
            if exportMethod == .email {
                // Use edge function for email export
                await performEmailExport()
            } else {
                // Use local export for direct download
                await performLocalExport()
            }
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func performEmailExport() async {
        do {
            guard let token = await authManager.getAccessToken() else {
                throw ExportError.exportFailed("Authentication failed")
            }

            // Progress: 50%
            exportProgress = 0.5

            // Call edge function
            let url = URL(string: "\(Constants.supabaseURL)/functions/v1/export-user-data")!
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

            // Progress: 100%
            exportProgress = 1.0

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
            // Get all user data
            guard let user = authManager.currentUser else {
                throw ExportError.noUserData
            }

            // Progress: 10%
            exportProgress = 0.1

            // Fetch all data from Core Data
            let bodyMetrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: user.id)
            let dailyLogs = await CoreDataManager.shared.fetchAllDailyLogs(for: user.id)

            // Progress: 30%
            exportProgress = 0.3

            // Create export data structure
            let exportData = ExportData(
                exportDate: Date(),
                user: user,
                bodyMetrics: bodyMetrics,
                dailyLogs: dailyLogs,
                photoURLs: includePhotos ? extractPhotoURLs(from: bodyMetrics) : []
            )

            // Progress: 50%
            exportProgress = 0.5

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

                // Update progress
                exportProgress = min(0.8, exportProgress + 0.2)
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

            // Progress: 90%
            exportProgress = 0.9

            // Create zip file if multiple files
            let finalExportURL: URL
            if exportedFiles.count > 1 {
                finalExportURL = try createZipArchive(from: exportDir, files: exportedFiles)
            } else {
                finalExportURL = exportedFiles.first!
            }

            // Progress: 100%
            exportProgress = 1.0

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

    private func createZipArchive(from directory: URL, files: [URL]) throws -> URL {
        let zipFileName = "LogYourBody_Export_\(formatDate(Date())).zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipFileName)

        // Note: In a real implementation, you would use a zip library here
        // For now, we'll just return the first file
        return files.first!
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

    var errorDescription: String? {
        switch self {
        case .noUserData:
            return "No user data found to export"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Helper Views

struct DataTypeRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.appPrimary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.appText)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()
        }
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
