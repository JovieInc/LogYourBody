//
// BackgroundTaskDetailsSheet.swift
// LogYourBody
//
import SwiftUI

// MARK: - Background Task Details Sheet

/// A sheet that shows details of all active background tasks
struct BackgroundTaskDetailsSheet: View {
    @ObservedObject var taskMonitor: BackgroundTaskMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var showCancelAllConfirmation = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if taskMonitor.activeTasks.isEmpty {
                    emptyStateView
                } else {
                    taskListView
                }
            }
            .navigationTitle("Background Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.appPrimary)
                }

                if taskMonitor.activeTasks.contains(where: { $0.canCancel }) {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showCancelAllConfirmation = true
                        } label: {
                            Text("Cancel All")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Cancel All Tasks",
                isPresented: $showCancelAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel All Tasks", role: .destructive) {
                    taskMonitor.cancelAllTasks()
                    dismiss()
                }
                Button("Keep Running", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel all background tasks? This cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("All Tasks Complete")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.appText)

            Text("No background tasks are currently running")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                dismiss()
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(taskMonitor.activeTasks.sorted { $0.type.priority > $1.type.priority }) { task in
                    TaskRow(task: task) {
                        taskMonitor.cancelTask(task)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    let task: BackgroundTaskInfo
    let onCancel: () -> Void

    @State private var showCancelConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            AnimatedTaskIcon(taskType: task.type, size: 28, color: .appPrimary)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appText)

                if let subtitle = task.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(2)
                }

                // Progress info
                if let progressText = task.progressText {
                    HStack(spacing: 6) {
                        if let progress = task.progress {
                            ProgressView(value: progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .appPrimary))
                                .frame(maxWidth: 100)
                        }

                        Text(progressText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.appTextSecondary)
                    }
                    .padding(.top, 4)
                }

                // Error state
                if task.isFailed, let error = task.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Cancel button
            if task.canCancel {
                Button {
                    showCancelConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.appTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.appCard)
        .cornerRadius(12)
        .confirmationDialog(
            "Cancel Task",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel \(task.type.rawValue)", role: .destructive) {
                onCancel()
            }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel this task?")
        }
    }
}

// MARK: - Preview

#Preview {
    BackgroundTaskDetailsSheet(
        taskMonitor: {
            let monitor = BackgroundTaskMonitor.shared
            return monitor
        }()
    )
}
