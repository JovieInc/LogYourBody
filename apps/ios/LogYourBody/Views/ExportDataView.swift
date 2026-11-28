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
    @State private var exportFlight = LocalExportFlight()
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
        Form {
            Section {
                Label("Your data, on your terms", systemImage: "lock.document.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Export your data")
                    .font(.title2.weight(.bold))
                Text(
                    "Download a copy anytime. Nothing is removed from LogYourBody, and the included data is shown before export."
                )
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Section {
                Picker("Delivery method", selection: $exportMethod) {
                    ForEach(ExportMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export_delivery_method_picker")

                Text(exportMethod.description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if exportMethod == .download {
                    Label(
                        "Direct download contains one JSON file and does not include progress photos.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Delivery")
            }

            Section("Included") {
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

            Section {
                Text(
                    exportMethod == .email
                        ? "A secure download link will be sent to your registered email address and expires after 24 hours."
                        : "The JSON file is saved to your device. Share it only with people and services you trust."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Email support about an export") {
                    requestExportViaEmail()
                }
                .accessibilityHint("Opens an email to LogYourBody support.")
            }

            Section {
                Button {
                    exportData()
                } label: {
                    Label(
                        exportMethod == .email ? "Email secure link" : "Download JSON",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isExportDisabled)
                .accessibilityIdentifier("export_data_action")
                .accessibilityHint(
                    exportMethod == .email
                        ? "Sends a secure export link to your registered email address."
                        : "Prepares a JSON export on this device."
                )
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .overlay {
            if isExporting {
                exportProgressOverlay
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        // The navigation-bar Cancel accessibility frame stays 36 points tall.
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Cancel export")
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
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
        .worldClassScreen(.exportData)
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Preparing your data")
                    .font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing your data")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Export Functionality

    private func exportData() {
        guard LocalExportCoordinator.start(flight: exportFlight, operation: { @MainActor in
            await self.performExport()
        }) != nil else { return }
        isExporting = true
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
        defer { isExporting = false }
        if exportMethod == .email {
            await performEmailExport()
        } else {
            await performLocalExport()
        }
    }

    @MainActor
    private func performEmailExport() async {
        do {
            guard let token = await authManager.getAccessToken() else {
                throw ExportError.exportFailed("Authentication failed")
            }

            guard let baseURL = URL(string: Configuration.apiBaseURL),
                  let url = URL(string: "/api/auth/mobile/export", relativeTo: baseURL)?.absoluteURL else {
                throw ExportError.exportFailed("Invalid server configuration")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ExportError.exportFailed("Server error")
            }

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "LogYourBody_Export_\(formatDate(Date())).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            exportedFileURL = fileURL

            successMessage = "Your export is ready."
            showShareSheet = true
        } catch {
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
            guard let user = authManager.currentUser else {
                throw ExportError.noUserData
            }

            let formats = localExportFormats()
            let heightCm = user.profile?.height
            let includePhotoFiles = includePhotos
            let read = await CoreDataManager.shared.fetchExportValueSnapshots(for: user.id)
            let result = try await LocalExportWork.write(LocalExportRequest(
                user: user,
                snapshots: read.snapshots,
                formats: formats,
                includePhotos: includePhotoFiles,
                heightCm: heightCm
            ))
            guard case .file(let file) = result else {
                throw ExportError.unsupportedDirectDownload
            }
            exportedFileURL = file.url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func localExportFormats() -> Set<LocalExportFormat> {
        Set(selectedFormats.map { format in
            switch format {
            case .json:
                return LocalExportFormat.json
            case .csv:
                return LocalExportFormat.csv
            }
        })
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
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: (@MainActor (Bool, Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { [onCompletion] _, completed, _, error in
            guard let onCompletion else { return }
            let failed = error != nil
            Task { @MainActor in onCompletion(completed, failed) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportDataView()
        .environmentObject(AuthManager.shared)
}
