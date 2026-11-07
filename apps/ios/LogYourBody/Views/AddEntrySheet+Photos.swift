import SwiftUI

extension AddEntrySheet {
// MARK: - Photo Entry View
    var photoEntryView: some View {
        VStack(spacing: 16) {
            if selectedPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.appTextTertiary)

                    Text("Select progress photos")
                        .font(.appHeadline)

                    Text(
                        "Photos will be automatically dated based on when they were taken. " +
                            "You can select multiple photos for bulk upload."
                    )
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                    AppPhotosPicker(maxSelectionCount: 10) { assets in
                        await MainActor.run {
                            selectedPhotos = assets
                            if !assets.isEmpty && !hasPromptedDeletePhotos {
                                showDeletePhotosPrompt = true
                            }
                        }
                    } label: {
                        Label("Choose Photos", systemImage: "photo.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
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
                        .disabled(!PhotoUploadBatchPolicy.canChangeSelection(isProcessing: isProcessingPhotos))
                    }

                    if isProcessingPhotos {
                        VStack(spacing: 12) {
                            ProgressView(value: photoProgress)
                                .tint(.appPrimary)

                            Text(
                                PhotoUploadBatchPolicy.progressText(
                                    processedCount: processedCount,
                                    totalCount: processingPhotoCount
                                )
                            )
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
}
