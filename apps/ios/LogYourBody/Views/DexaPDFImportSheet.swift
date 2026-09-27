import SwiftUI

struct DexaPDFFileSelection: Identifiable {
    let id = UUID()
    let url: URL
}

extension Notification.Name {
    static let dexaPDFReceived = Notification.Name("dexaPDFReceived")
}

struct DexaPDFImportSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let fileURL: URL

    @State private var scans: [DexaPDFScan] = []
    @State private var isReading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedSummary: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected report") {
                    Label(fileURL.lastPathComponent, systemImage: "doc.text")
                        .lineLimit(2)
                    Text("The scan values are extracted from this PDF. The original file is not saved to your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if isReading {
                        ProgressView("Reading report…")
                    } else if let savedSummary {
                        Label(savedSummary, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appError)
                    } else {
                        ForEach(Array(scans.enumerated()), id: \.offset) { _, scan in
                            scanRow(scan)
                        }

                        Button {
                            saveScans()
                        } label: {
                            if isSaving {
                                ProgressView("Saving scans…")
                            } else {
                                Label("Add to timeline", systemImage: "plus.circle")
                            }
                        }
                        .disabled(isSaving)
                        .accessibilityIdentifier("dexa_pdf_import_save")
                    }
                } header: {
                    Text("Scan history")
                } footer: {
                    Text("Existing entries on the same date are kept. Every scan is saved with its source and date.")
                }
            }
            .navigationTitle("Import scan PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await readReport()
            }
        }
    }

    private func scanRow(_ scan: DexaPDFScan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scan.date)
                .font(.headline)
            Text(scan.source ?? "DEXA scan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(measurementSummary(for: scan))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func measurementSummary(for scan: DexaPDFScan) -> String {
        var values = ["\(scan.weight.formatted(.number.precision(.fractionLength(0...1)))) \(scan.weightUnit)"]
        if let bodyFat = scan.bodyFatPercentage {
            values.append("\(bodyFat.formatted(.number.precision(.fractionLength(0...1))))% body fat")
        }
        if let muscleMass = scan.muscleMass {
            values.append("\(muscleMass.formatted(.number.precision(.fractionLength(0...1)))) muscle mass")
        }
        return values.joined(separator: " · ")
    }

    @MainActor
    private func readReport() async {
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { fileURL.stopAccessingSecurityScopedResource() }
        }

        do {
            guard authManager.currentUser?.id != nil,
                  let accessToken = await authManager.getAccessToken() else {
                throw DexaPDFImportError.server("Sign in before importing a scan.")
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            scans = try await DexaPDFImportCoordinator.shared.parse(
                fileData: data,
                fileName: fileURL.lastPathComponent,
                accessToken: accessToken
            )
            isReading = false
        } catch {
            errorMessage = error.localizedDescription
            isReading = false
        }
    }

    private func saveScans() {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "Sign in before importing a scan."
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                let plan = try await DexaPDFImportCoordinator.shared.save(scans: scans, userId: userId)
                let count = plan.results.count
                let scanWord = count == 1 ? "scan" : "scans"
                let timelineWord = plan.metrics.count == 1 ? "dated timeline entry" : "dated timeline entries"
                savedSummary = count == 0
                    ? "These scans were already imported."
                    : "Added \(count) \(scanWord) and \(plan.metrics.count) new \(timelineWord)."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
