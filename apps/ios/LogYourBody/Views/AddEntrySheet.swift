//
// AddEntrySheet.swift
// LogYourBody
//
import SwiftUI
import PhotosUI

struct AddEntrySheet: View {
    @Environment(\.dismiss)
    var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    @State private var selectedTab: Int
    @State private var selectedDate = Date()
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem

    init(isPresented: Binding<Bool>, initialTab: Int = 0) {
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }

    // Weight entry
    @State private var weight: String = ""
    @State private var weightUnit: String = ""
    @State private var weightError: String?

    // Body fat entry
    @State private var bodyFat: String = ""
    @State private var bodyFatMethod = "Visual"
    @State private var bodyFatError: String?

    // Photo entry
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoProgress: Double = 0
    @State private var processedCount = 0
    @State private var photoIdentifiers: [String] = []  // Store PHAsset identifiers for deletion

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeletePhotosPrompt = false
    @AppStorage(Constants.deletePhotosAfterImportKey) private var deletePhotosAfterImport = false
    @AppStorage(Constants.hasPromptedDeletePhotosKey) private var hasPromptedDeletePhotos = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Entry Type", selection: $selectedTab) {
                    Label("Weight", systemImage: "scalemass").tag(0)
                    Label("Body Fat", systemImage: "percent").tag(1)
                    Label("Photos", systemImage: "photo.fill").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 12)
                .accessibilityLabel("Entry type selector")
                .accessibilityHint("Select the type of entry you want to add")

                // Date picker (common for all tabs)
                HStack {
                    Text("Date")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    Spacer()

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case 0:
                        weightEntryView
                    case 1:
                        bodyFatEntryView
                    case 2:
                        photoEntryView
                    default:
                        EmptyView()
                    }
                }

                // Save button
                Button(action: saveEntry) {
                    HStack {
                        if isProcessingPhotos {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Text(saveButtonText)
                                .font(.appBody)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(canSave ? Color.white : Color.appBorder)
                    .foregroundColor(canSave ? .black : .white)
                    .cornerRadius(Constants.cornerRadius)
                }
                .disabled(!canSave || isProcessingPhotos)
                .padding()
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Delete Photos After Import?", isPresented: $showDeletePhotosPrompt) {
                Button("Keep Photos", role: .cancel) {
                    deletePhotosAfterImport = false
                    hasPromptedDeletePhotos = true
                }
                Button("Delete After Import") {
                    deletePhotosAfterImport = true
                    hasPromptedDeletePhotos = true
                }
            } message: {
                Text("Would you like to automatically delete photos from your camera roll after importing them into the app? You can change this later in Settings.")
            }
            .onAppear {
                // Set default weight unit based on user preference
                if weightUnit.isEmpty {
                    weightUnit = currentSystem.weightUnit
                }
            }
        }
    }

    // MARK: - Weight Entry View
    private var weightEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your weight")
                .font(.appHeadline)
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("0.0", text: $weight)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .modernTextFieldStyle()
                        .accessibilityLabel("Weight value")
                        .accessibilityHint("Enter your weight")
                        .submitLabel(.done)
                        .onChange(of: weight) { _, newValue in
                            validateWeight(newValue)
                        }

                    Picker("Unit", selection: $weightUnit) {
                        Text("kg").tag("kg")
                        Text("lbs").tag("lbs")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                    .accessibilityLabel("Weight unit")
                }

                // Helper text
                if let error = weightError {
                    Text(error)
                        .font(.appBodySmall)
                        .foregroundColor(.error)
                        .accessibilityLabel("Weight validation error: \(error)")
                } else {
                    Text(weightUnit == "kg" ? "Valid range: 20-300 kg" : "Valid range: 44-660 lbs")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Body Fat Entry View
    private var bodyFatEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter body fat percentage")
                .font(.appHeadline)
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("0.0", text: $bodyFat)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .modernTextFieldStyle()
                        .accessibilityLabel("Body fat percentage value")
                        .accessibilityHint("Enter your body fat percentage")
                        .submitLabel(.done)
                        .onChange(of: bodyFat) { _, newValue in
                            validateBodyFat(newValue)
                        }

                    Text("%")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }

                // Helper text
                if let error = bodyFatError {
                    Text(error)
                        .font(.appBodySmall)
                        .foregroundColor(.error)
                        .accessibilityLabel("Body fat validation error: \(error)")
                } else {
                    Text("Valid range: 3-50%")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Measurement Method")
                    .font(.appBodySmall)
                    .foregroundColor(.appTextSecondary)

                Picker("Method", selection: $bodyFatMethod) {
                    Text("Visual Estimate").tag("Visual")
                    Text("Body Scan").tag("Scan")
                    Text("Calipers").tag("Calipers")
                    Text("Bioelectrical").tag("BIA")
                    Text("DEXA").tag("DEXA")
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Body fat measurement method")
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Photo Entry View
    private var photoEntryView: some View {
        VStack(spacing: 16) {
            if selectedPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.appTextTertiary)

                    Text("Select progress photos")
                        .font(.appHeadline)

                    Text("Photos will be automatically dated based on when they were taken. You can select multiple photos for bulk upload.")
                        .font(.appBody)
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Choose Photos", systemImage: "photo.fill")
                            .frame(height: 48)
                            .frame(maxWidth: .infinity)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(Constants.cornerRadius)
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedPhotos) { _, newPhotos in
                        if !newPhotos.isEmpty && !hasPromptedDeletePhotos {
                            showDeletePhotosPrompt = true
                        }
                    }
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(selectedPhotos.count) photo\(selectedPhotos.count == 1 ? "" : "s") selected")
                            .font(.appHeadline)

                        Spacer()

                        Button("Change") {
                            selectedPhotos = []
                        }
                        .foregroundColor(.appPrimary)
                    }

                    if isProcessingPhotos {
                        VStack(spacing: 12) {
                            ProgressView(value: photoProgress)
                                .tint(.appPrimary)

                            Text("Processing \(processedCount + 1) of \(selectedPhotos.count)")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
            }

            Spacer()
        }
    }

    // MARK: - Computed Properties
    private var canSave: Bool {
        switch selectedTab {
        case 0:
            return !weight.isEmpty && Double(weight) != nil && weightError == nil
        case 1:
            return !bodyFat.isEmpty && Double(bodyFat) != nil && bodyFatError == nil
        case 2:
            return !selectedPhotos.isEmpty
        default:
            return false
        }
    }

    private var saveButtonText: String {
        switch selectedTab {
        case 0:
            return "Save Weight"
        case 1:
            return "Save Body Fat"
        case 2:
            return selectedPhotos.count > 1 ? "Upload \(selectedPhotos.count) Photos" : "Upload Photo"
        default:
            return "Save"
        }
    }

    // MARK: - Actions
    private func saveEntry() {
        guard let userId = authManager.currentUser?.id else { return }

        switch selectedTab {
        case 0:
            saveWeight(userId: userId)
        case 1:
            saveBodyFat(userId: userId)
        case 2:
            Task {
                await savePhotos(userId: userId)
            }
        default:
            break
        }
    }

    private func saveWeight(userId: String) {
        guard let weightValue = Double(weight) else { return }

        let weightInKg = weightUnit == "lbs" ? weightValue * 0.453592 : weightValue

        Task {
            _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                for: selectedDate,
                weight: weightInKg,
                userId: userId
            )

            // Update widget data
            await WidgetDataManager.shared.updateWidgetData()

            RealtimeSyncManager.shared.syncIfNeeded()
        }

        dismiss()
    }

    private func saveBodyFat(userId: String) {
        guard let bodyFatValue = Double(bodyFat) else { return }

        Task {
            _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                for: selectedDate,
                bodyFatPercentage: bodyFatValue,
                userId: userId
            )

            // Update widget data
            await WidgetDataManager.shared.updateWidgetData()

            RealtimeSyncManager.shared.syncIfNeeded()
        }

        dismiss()
    }

    private func savePhotos(userId: String) async {
        isProcessingPhotos = true
        photoProgress = 0
        processedCount = 0
        photoIdentifiers.removeAll()

        for (index, item) in selectedPhotos.enumerated() {
            do {
                // Extract PHAsset identifier if available
                if let identifier = item.itemIdentifier {
                    photoIdentifiers.append(identifier)
                }

                // Load the photo data
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }

                // Extract date from metadata
                let photoDate = PhotoMetadataService.shared.extractDate(from: data) ?? selectedDate

                // Create or get metrics for this date
                let metrics = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: photoDate,
                    userId: userId
                )

                // Upload the photo
                _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                    for: metrics,
                    image: image
                )

                processedCount = index + 1
                photoProgress = Double(processedCount) / Double(selectedPhotos.count)
            } catch {
                // print("Failed to process photo \(index): \(error)")
            }
        }

        // Delete photos from camera roll if enabled
        if deletePhotosAfterImport && !photoIdentifiers.isEmpty {
            await deletePhotosFromLibrary()
        }

        isProcessingPhotos = false
        RealtimeSyncManager.shared.syncIfNeeded()
        dismiss()
    }

    private func deletePhotosFromLibrary() async {
        guard !photoIdentifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: photoIdentifiers, options: nil)

        guard fetchResult.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
        } catch {
            // Silently fail - don't interrupt the user flow if deletion fails
            // print("Failed to delete photos: \(error)")
        }
    }

    // MARK: - Validation Functions

    private func validateWeight(_ value: String) {
        guard !value.isEmpty else {
            weightError = nil
            return
        }

        guard let weightValue = Double(value) else {
            weightError = "Please enter a valid number"
            return
        }

        let minWeight = weightUnit == "kg" ? 20.0 : 44.0
        let maxWeight = weightUnit == "kg" ? 300.0 : 660.0

        if weightValue < minWeight {
            weightError = "Weight must be at least \(Int(minWeight)) \(weightUnit)"
        } else if weightValue > maxWeight {
            weightError = "Weight must be less than \(Int(maxWeight)) \(weightUnit)"
        } else {
            weightError = nil
        }
    }

    private func validateBodyFat(_ value: String) {
        guard !value.isEmpty else {
            bodyFatError = nil
            return
        }

        guard let bfValue = Double(value) else {
            bodyFatError = "Please enter a valid number"
            return
        }

        if bfValue < 3.0 {
            bodyFatError = "Body fat must be at least 3%"
        } else if bfValue > 50.0 {
            bodyFatError = "Body fat must be less than 50%"
        } else {
            bodyFatError = nil
        }
    }
}

#Preview {
    AddEntrySheet(isPresented: .constant(true))
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
