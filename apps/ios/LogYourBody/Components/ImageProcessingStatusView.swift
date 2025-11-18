//
// ImageProcessingStatusView.swift
// LogYourBody
//
import SwiftUI
struct ImageProcessingStatusView: View {
    @StateObject private var processingService = ImageProcessingService.shared

    var body: some View {
        if processingService.activeProcessingCount > 0 {
            VStack(spacing: 0) {
                // Compact header
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14))
                        .foregroundColor(.appPrimary)

                    Text("Processing \(processingService.activeProcessingCount) image\(processingService.activeProcessingCount > 1 ? "s" : "")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appText)

                    Spacer()

                    if processingService.activeProcessingCount == 1,
                       let task = processingService.processingTasks.first(where: { $0.status != .completed && $0.status != .failed }) {
                        ProcessingProgressView(progress: task.progress)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Task list
                if processingService.processingTasks.count > 1 {
                    Divider()
                        .background(Color.appBorder)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(processingService.processingTasks.filter { $0.status != .completed }) { task in
                                ProcessingTaskRow(task: task)
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxHeight: 150)
                }
            }
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct ProcessingTaskRow: View {
    let task: ImageProcessingService.ProcessingTask

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .frame(width: 20)

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appText)

                if let error = task.error {
                    Text(error.localizedDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Progress
            if task.status != .completed && task.status != .failed {
                ProcessingProgressView(progress: task.progress, size: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appCard.opacity(0.5))
        .cornerRadius(8)
    }

    @ViewBuilder

    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
        case .detecting:
            Image(systemName: "viewfinder")
                .font(.system(size: 12))
                .foregroundColor(.appPrimary)
        case .cropping:
            Image(systemName: "crop")
                .font(.system(size: 12))
                .foregroundColor(.appPrimary)
        case .removingBackground:
            Image(systemName: "scissors")
                .font(.system(size: 12))
                .foregroundColor(.appPrimary)
        case .finalizing:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.appPrimary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
    }

    private var statusText: String {
        switch task.status {
        case .pending:
            return "Waiting..."
        case .detecting:
            return "Detecting person..."
        case .cropping:
            return "Auto-cropping..."
        case .removingBackground:
            return "Removing background..."
        case .finalizing:
            return "Finalizing..."
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }
}

struct ProcessingProgressView: View {
    let progress: Double
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appBorder, lineWidth: 2)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.appPrimary, lineWidth: 2)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}


// MARK: - Integration Helper

extension View {
    func imageProcessingOverlay() -> some View {
        self.overlay(
            VStack {
                ImageProcessingStatusView()
                    .padding(.top, 50) // Below navigation
                Spacer()
            }
        )
    }
}
