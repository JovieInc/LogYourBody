//
// BulkPhotoImportView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct BulkPhotoImportView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scanner = PhotoLibraryScanner.shared
    @StateObject private var importManager = BulkImportManager.shared
    @Environment(\.dismiss)
    var dismiss
    @State private var selectedPhotos: Set<UUID> = []
    @State private var showPermissionAlert = false
    @State private var showImportConfirmation = false
    @State private var isImporting = false
    @State private var showWelcomeScreen = true
    @State private var hasStartedScan = false
    @State private var importCompletion: ImportCompletion?

    private struct ImportCompletion: Equatable {
        let importedCount: Int
        let failedCount: Int

        var title: String {
            failedCount == 0 ? "Photos imported" : "Import complete"
        }

        var message: String {
            if failedCount == 0 {
                return "\(importedCount) photo\(importedCount == 1 ? "" : "s") added to your timeline."
            }
            return "\(importedCount) added. \(failedCount) could not be imported; you can try those again later."
        }
    }

    private var selectedCount: Int {
        selectedPhotos.count
    }

    private var allPhotosSelected: Bool {
        selectedPhotos.count == scanner.scannedPhotos.count && !scanner.scannedPhotos.isEmpty
    }

    var body: some View {
        ZStack {
            Color.jovieCanvas
                .ignoresSafeArea()

            content
        }
        .navigationTitle("Import Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !scanner.scannedPhotos.isEmpty && !isImporting {
                    Button(allPhotosSelected ? "Clear" : "Select All") {
                        if allPhotosSelected {
                            selectedPhotos.removeAll()
                        } else {
                            selectedPhotos = Set(scanner.scannedPhotos.map { $0.id })
                        }
                    }
                    .jovieTouchTarget()
                }
            }
        }
        .alert("Photo Library Access", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("LogYourBody needs access to your photo library to scan for progress photos. Please enable access in Settings.")
        }
        .confirmationDialog("Import Photos", isPresented: $showImportConfirmation) {
            Button("Import \(selectedCount) Photos") {
                startImport()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will import \(selectedCount) photos to your progress gallery. The import will continue in the background.")
        }
        .onAppear {
            // Check if already scanning or importing
            if scanner.isScanning || importManager.isImporting {
                showWelcomeScreen = false
                hasStartedScan = true
            }
        }
    }

    @ViewBuilder

    private var content: some View {
        if let importCompletion {
            importCompletionView(importCompletion)
        } else if showWelcomeScreen && !hasStartedScan {
            welcomeView
        } else if scanner.authorizationStatus == .notDetermined {
            permissionRequestView
        } else if scanner.authorizationStatus == .denied || scanner.authorizationStatus == .restricted {
            accessDeniedView
        } else if scanner.isScanning {
            scanningView
        } else if scanner.scannedPhotos.isEmpty && hasStartedScan {
            noPhotosFoundView
        } else if isImporting || importManager.isImporting {
            importingView
        } else {
            photoSelectionView
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.colors.info.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundColor(theme.colors.info)
            }

            VStack(spacing: 12) {
                Text("Bulk Photo Import")
                    .font(theme.typography.displaySmall)

                Text("Find likely progress photos and choose exactly which ones to add, keeping their original dates.")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Scans on this iPhone before anything is imported", systemImage: "lock.shield")
                    Label("Preserves original photo dates", systemImage: "calendar")
                    Label("Uploads only the photos you select", systemImage: "checkmark.circle")
                }
                .font(theme.typography.bodySmall)
                .foregroundColor(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.md)
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous))
                .padding(.horizontal, JovieTokens.screenInset)
            }

            Spacer()

            BaseButton(
                "Start Scanning",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    fullWidth: true
                ),
                action: {
                    showWelcomeScreen = false
                    hasStartedScan = true
                    checkPermissionAndScan()
                }
            )
            .accessibilityIdentifier("bulk_photo_import_start_scanning")
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - Permission Request View

    private var permissionRequestView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.colors.info.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "photo.stack")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundColor(theme.colors.info)
            }

            VStack(spacing: 12) {
                Text("Access Your Photos")
                    .font(theme.typography.displaySmall)

                Text("Allow access to find likely progress photos on this iPhone. No photo is added until you choose it.")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)
            }

            Spacer()

            BaseButton(
                "Allow Access",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    fullWidth: true
                ),
                action: {
                    Task {
                        let authorized = await scanner.requestAuthorization()
                        if authorized {
                            await scanner.scanPhotoLibrary()
                        } else {
                            showPermissionAlert = true
                        }
                    }
                }
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - Access Denied View

    private var accessDeniedView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            Image(systemName: "photo.slash")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundColor(theme.colors.error)

            VStack(spacing: 12) {
                Text("Photo Access Required")
                    .font(theme.typography.displaySmall)

                Text("Please enable photo library access in Settings to import progress photos")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)
            }

            Spacer()

            BaseButton(
                "Open Settings",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    fullWidth: true
                ),
                action: {
                    openSettings()
                }
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(theme.colors.border, lineWidth: 3)
                    .frame(width: 88, height: 88)

                Circle()
                    .trim(from: 0, to: scanner.scanProgress)
                    .stroke(theme.colors.info, lineWidth: 3)
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : theme.animation.subtle, value: scanner.scanProgress)

                Image(systemName: "photo.stack")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundColor(theme.colors.info)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scanning photos, \(Int(scanner.scanProgress * 100)) percent complete")

            VStack(spacing: 12) {
                Text("Scanning photos")
                    .font(theme.typography.displaySmall)

                Text("Looking for likely progress photos on this iPhone.")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)

                if scanner.scanProgress > 0 {
                    Text("\(Int(scanner.scanProgress * 100))%")
                        .font(theme.typography.labelMedium)
                        .foregroundColor(theme.colors.textSecondary)
                }
            }

            Spacer()

            BaseButton(
                "Cancel",
                configuration: ButtonConfiguration(
                    style: .tertiary
                ),
                action: {
                    scanner.cancelScan()
                    dismiss()
                }
            )
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - No Photos Found View

    private var noPhotosFoundView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundColor(theme.colors.textSecondary)

            VStack(spacing: 12) {
                Text("No Progress Photos Found")
                    .font(theme.typography.displaySmall)

                Text("We couldn't find any photos that look like progress photos in your library")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)
            }

            Spacer()

            BaseButton(
                "Done",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    fullWidth: true
                ),
                action: {
                    dismiss()
                }
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - Photo Selection View

    private var photoSelectionView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Found \(scanner.scannedPhotos.count) potential photos")
                    .font(theme.typography.headlineSmall)

                Text("Select the photos you want to import")
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface)

            // Photo Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: JovieTokens.itemGap),
                    GridItem(.flexible(), spacing: JovieTokens.itemGap),
                    GridItem(.flexible(), spacing: JovieTokens.itemGap)
                ], spacing: JovieTokens.itemGap) {
                    ForEach(scanner.scannedPhotos) { photo in
                        PhotoGridItem(
                            photo: photo,
                            isSelected: selectedPhotos.contains(photo.id)
                        ) {
                            toggleSelection(for: photo)
                        }
                    }
                }
                .padding(JovieTokens.compactInset)
            }

            // Import Button
            if selectedCount > 0 {
                VStack(spacing: 0) {
                    Divider()

                    BaseButton(
                        "Import \(selectedCount) Photo\(selectedCount == 1 ? "" : "s")",
                        configuration: ButtonConfiguration(
                            style: .custom(background: .jovieAction, foreground: .jovieActionText),
                            fullWidth: true,
                            icon: "square.and.arrow.down"
                        ),
                        action: {
                            showImportConfirmation = true
                        }
                    )
                    .padding(JovieTokens.compactInset)
                    .background(theme.colors.surface)
                }
            }
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(theme.colors.border, lineWidth: 3)
                    .frame(width: 88, height: 88)

                Circle()
                    .trim(from: 0, to: importManager.overallProgress)
                    .stroke(theme.colors.info, lineWidth: 3)
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : theme.animation.subtle, value: importManager.overallProgress)

                VStack(spacing: 4) {
                    Text("\(importManager.completedCount)")
                        .font(theme.typography.displaySmall)
                    Text("of \(importManager.totalCount)")
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Importing photos, \(importManager.completedCount) of \(importManager.totalCount) complete")

            VStack(spacing: 12) {
                Text("Importing photos")
                    .font(theme.typography.displaySmall)

                if let currentPhoto = importManager.currentPhotoName {
                    Text(currentPhoto)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            BaseButton(
                "Continue in Background",
                configuration: ButtonConfiguration(
                    style: .tertiary
                ),
                action: {
                    dismiss()
                }
            )
            .padding(.bottom, JovieTokens.sectionGap)
        }
    }

    // MARK: - Helper Methods

    private func checkPermissionAndScan() {
        // Prevent multiple scans
        guard !scanner.isScanning else { return }

        scanner.checkAuthorizationStatus()

        if scanner.authorizationStatus == .authorized {
            Task {
                await scanner.scanPhotoLibrary()
            }
        }
    }

    private func toggleSelection(for photo: ScannedPhoto) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }

    private func startImport() {
        guard !importManager.isImporting else { return }

        let photosToImport = scanner.scannedPhotos.filter { selectedPhotos.contains($0.id) }
        isImporting = true
        importCompletion = nil

        Task {
            await importManager.importPhotos(photosToImport)
            await MainActor.run {
                isImporting = false
                importCompletion = ImportCompletion(
                    importedCount: max(importManager.completedCount - importManager.failedCount, 0),
                    failedCount: importManager.failedCount
                )
                UIAccessibility.post(
                    notification: .announcement,
                    argument: importCompletion?.message
                )
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func importCompletionView(_ completion: ImportCompletion) -> some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Spacer()

            Image(systemName: completion.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundColor(completion.failedCount == 0 ? theme.colors.success : theme.colors.warning)

            VStack(spacing: 12) {
                Text(completion.title)
                    .font(theme.typography.displaySmall)

                Text(completion.message)
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JovieTokens.screenInset)
            }

            Spacer()

            BaseButton(
                "Done",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    fullWidth: true
                ),
                action: { dismiss() }
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.bottom, JovieTokens.sectionGap)
        }
        .accessibilityIdentifier("bulk_photo_import_completion")
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let photo: ScannedPhoto
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Photo
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                        .fill(Color.jovieSurface)
                        .frame(height: 120)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .appTextTertiary))
                        )
                }

                // Selection overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                        .fill(Color.jovieMetricAccent.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                                .stroke(Color.jovieMetricAccent, lineWidth: 3)
                        )
                }

                // Selection checkmark
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.jovieMetricAccent : Color.black.opacity(0.5))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(8)

                // Date badge
                VStack {
                    Spacer()
                    HStack {
                        Text(photo.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Spacer()
                    }
                    .padding(8)
                }

                // Confidence indicator
                if photo.confidence > 0.85 {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Photo from \(photo.date.formatted(.dateTime.month(.wide).day().year()))\(photo.confidence > 0.85 ? ", high-confidence suggestion" : ", suggested progress photo")"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(isSelected ? "remove from" : "add to") import")
        .onAppear {
            Task {
                thumbnail = await PhotoLibraryScanner.shared.loadThumbnail(for: photo.asset)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BulkPhotoImportView()
            .environmentObject(AuthManager.shared)
    }
}
