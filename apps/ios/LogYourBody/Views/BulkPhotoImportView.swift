//
// BulkPhotoImportView.swift
// LogYourBody
//
import SwiftUI
import Photos

struct BulkPhotoImportView: View {
    @EnvironmentObject var authManager: AuthManager
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

    private var selectedCount: Int {
        selectedPhotos.count
    }

    private var allPhotosSelected: Bool {
        selectedPhotos.count == scanner.scannedPhotos.count && !scanner.scannedPhotos.isEmpty
    }

    var body: some View {
        ZStack {
            Color.appBackground
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
                }
            }
        }
        .alert("Photo Library Access", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
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
        if showWelcomeScreen && !hasStartedScan {
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
        VStack(spacing: 40) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.appPrimary)
            }

            VStack(spacing: 16) {
                Text("Bulk Photo Import")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Scan your photo library for progress photos and import them with their original dates")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Analyzes photos to find potential progress photos", systemImage: "magnifyingglass")
                    Label("Preserves original photo dates", systemImage: "calendar")
                    Label("Import multiple photos at once", systemImage: "square.stack.3d.up")
                }
                .font(.footnote)
                .foregroundColor(.appTextSecondary)
                .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                BaseButton(
                    "Start Scanning",
                    configuration: ButtonConfiguration(
                        style: .custom(background: .appPrimary, foreground: .white),
                        fullWidth: true
                    ),
                    action: {
                        showWelcomeScreen = false
                        hasStartedScan = true
                        checkPermissionAndScan()
                    }
                )

                BaseButton(
                    "Cancel",
                    configuration: ButtonConfiguration(
                        style: .tertiary
                    ),
                    action: {
                        dismiss()
                    }
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Permission Request View

    private var permissionRequestView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "photo.stack")
                    .font(.system(size: 60))
                    .foregroundColor(.appPrimary)
            }

            VStack(spacing: 16) {
                Text("Access Your Photos")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Allow LogYourBody to scan your photo library for potential progress photos")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            BaseButton(
                "Allow Access",
                configuration: ButtonConfiguration(
                    style: .custom(background: .appPrimary, foreground: .white),
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
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Access Denied View

    private var accessDeniedView: some View {
        VStack(spacing: 40) {
            Spacer()

            Image(systemName: "photo.slash")
                .font(.system(size: 80))
                .foregroundColor(.appTextTertiary)

            VStack(spacing: 16) {
                Text("Photo Access Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Please enable photo library access in Settings to import progress photos")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            BaseButton(
                "Open Settings",
                configuration: ButtonConfiguration(
                    style: .custom(background: .appPrimary, foreground: .white),
                    fullWidth: true
                ),
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated scanner
            ZStack {
                Circle()
                    .stroke(Color.appBorder, lineWidth: 3)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: scanner.scanProgress)
                    .stroke(Color.appPrimary, lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: scanner.scanProgress)

                Image(systemName: "photo.stack")
                    .font(.system(size: 50))
                    .foregroundColor(.appPrimary)
            }

            VStack(spacing: 12) {
                Text("Scanning Photos...")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Analyzing your photo library for potential progress photos")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if scanner.scanProgress > 0 {
                    Text("\(Int(scanner.scanProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.appTextTertiary)
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
            .padding(.bottom, 40)
        }
    }

    // MARK: - No Photos Found View

    private var noPhotosFoundView: some View {
        VStack(spacing: 40) {
            Spacer()

            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 80))
                .foregroundColor(.appTextTertiary)

            VStack(spacing: 16) {
                Text("No Progress Photos Found")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We couldn't find any photos that look like progress photos in your library")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            BaseButton(
                "Done",
                configuration: ButtonConfiguration(
                    style: .custom(background: .appPrimary, foreground: .white),
                    fullWidth: true
                ),
                action: {
                    dismiss()
                }
            )
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Photo Selection View

    private var photoSelectionView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Found \(scanner.scannedPhotos.count) potential photos")
                    .font(.headline)

                Text("Select the photos you want to import")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
            }
            .padding()
            .background(Color.appCard)

            // Photo Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(scanner.scannedPhotos) { photo in
                        PhotoGridItem(
                            photo: photo,
                            isSelected: selectedPhotos.contains(photo.id)
                        ) {
                            toggleSelection(for: photo)
                        }
                    }
                }
                .padding()
            }

            // Import Button
            if selectedCount > 0 {
                VStack(spacing: 0) {
                    Divider()

                    BaseButton(
                        "Import \(selectedCount) Photo\(selectedCount == 1 ? "" : "s")",
                        configuration: ButtonConfiguration(
                            style: .custom(background: .appPrimary, foreground: .white),
                            fullWidth: true,
                            icon: "square.and.arrow.down"
                        ),
                        action: {
                            showImportConfirmation = true
                        }
                    )
                    .padding()
                    .background(Color.appCard)
                }
            }
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Progress
            ZStack {
                Circle()
                    .stroke(Color.appBorder, lineWidth: 3)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: importManager.overallProgress)
                    .stroke(Color.appPrimary, lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: importManager.overallProgress)

                VStack(spacing: 4) {
                    Text("\(importManager.completedCount)")
                        .font(.system(size: 32, weight: .bold))
                    Text("of \(importManager.totalCount)")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }

            VStack(spacing: 12) {
                Text("Importing Photos...")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let currentPhoto = importManager.currentPhotoName {
                    Text(currentPhoto)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
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
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helper Methods

    private func checkPermissionAndScan() {
        // Prevent multiple scans
        guard !scanner.isScanning else { return }

        scanner.checkAuthorizationStatus()

        if scanner.authorizationStatus == .authorized || scanner.authorizationStatus == .limited {
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
        // Prevent multiple imports
        guard !importManager.isImporting else { return }

        let photosToImport = scanner.scannedPhotos.filter { selectedPhotos.contains($0.id) }
        isImporting = true

        Task {
            await importManager.importPhotos(photosToImport)

            // Show success and dismiss
            await MainActor.run {
                // Show success notification in the import manager instead
                dismiss()
            }
        }
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
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appCard)
                        .frame(height: 120)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .appTextTertiary))
                        )
                }

                // Selection overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appPrimary.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.appPrimary, lineWidth: 3)
                        )
                }

                // Selection checkmark
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.appPrimary : Color.black.opacity(0.5))
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
                            .cornerRadius(4)
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
        .onAppear {
            Task {
                thumbnail = await PhotoLibraryScanner.shared.loadThumbnail(for: photo.asset)
            }
        }
    }
}

#Preview {
    NavigationView {
        BulkPhotoImportView()
            .environmentObject(AuthManager.shared)
    }
}
