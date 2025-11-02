//
// DashboardTaskBanner.swift
// LogYourBody
//
import SwiftUI

// MARK: - Dashboard Task Banner Organism

/// A floating banner that appears on the dashboard to show active background tasks
struct DashboardTaskBanner: View {
    @ObservedObject var taskMonitor: BackgroundTaskMonitor
    @State private var showDetails = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if let task = taskMonitor.primaryTask {
                bannerContent(for: task)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: taskMonitor.isAnyTaskActive)
        .sheet(isPresented: $showDetails) {
            BackgroundTaskDetailsSheet(taskMonitor: taskMonitor)
        }
        .confirmationDialog(
            "Cancel Task",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            if let task = taskMonitor.primaryTask {
                Button("Cancel \(task.type.rawValue)", role: .destructive) {
                    taskMonitor.cancelTask(task)
                }
                Button("Cancel All Tasks", role: .destructive) {
                    taskMonitor.cancelAllTasks()
                }
                Button("Continue", role: .cancel) {}
            }
        } message: {
            Text("Are you sure you want to cancel this task?")
        }
    }

    @ViewBuilder
    private func bannerContent(for task: BackgroundTaskInfo) -> some View {
        HStack(spacing: 12) {
            // Animated icon
            AnimatedTaskIcon(taskType: task.type, size: 22, color: .white)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    // Additional task count badge
                    if taskMonitor.additionalTaskCount > 0 {
                        Text("+\(taskMonitor.additionalTaskCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                            )
                    }
                }

                if let subtitle = task.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Progress indicator
            if let itemCount = task.itemCount {
                // Count-based progress
                Text("\(itemCount.current) of \(itemCount.total)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
            } else if let progress = task.progress {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }

            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            // Glassmorphism effect
            ZStack {
                // Background blur
                Color.appCard.opacity(0.8)

                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color.appPrimary.opacity(0.3),
                        Color.appPrimary.opacity(0.1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                // Border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
            .cornerRadius(12)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.buttonTapped()
            showDetails = true
        }
        .onLongPressGesture {
            if task.canCancel {
                HapticManager.shared.toggleChanged()
                showCancelConfirmation = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()

        VStack(spacing: 16) {
            // Scanning preview
            DashboardTaskBanner(
                taskMonitor: {
                    let monitor = BackgroundTaskMonitor.shared
                    // Simulate scanning task
                    return monitor
                }()
            )

            // Importing preview
            DashboardTaskBanner(
                taskMonitor: {
                    let monitor = BackgroundTaskMonitor.shared
                    // Simulate importing task
                    return monitor
                }()
            )

            Spacer()
        }
        .padding(.top, 60)
    }
}
