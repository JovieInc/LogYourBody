//
// ProfilePreparationView.swift
// LogYourBody
//
import SwiftUI
struct ProfilePreparationView: View {
    @Binding var onboardingData: OnboardingData
    let onComplete: () -> Void

    @StateObject private var uploadService = BackgroundPhotoUploadService.shared
    @State private var preparationSteps: [PreparationStep] = []
    @State private var showContinueButton = false
    @State private var minimumLoadTime = false
    @State private var currentStepIndex = 0

    struct PreparationStep: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        var status: StepStatus = .pending
    }

    enum StepStatus {
        case pending
        case inProgress
        case completed
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Title & subtitle
            VStack(spacing: 16) {
                Text("Getting Your Profile Ready")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Just a moment while we set everything up...")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)

            // Step list
            VStack(spacing: 24) {
                ForEach(Array(preparationSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 20) {
                        // Icon or progress indicator
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 48, height: 48)

                            if step.status == .inProgress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                    .transition(.opacity)
                            } else if step.status == .completed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .transition(.scale.combined(with: .opacity))
                                    .scaleEffect(step.status == .completed ? 1 : 0.5)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: step.status)
                            } else {
                                Image(systemName: step.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }

                        Text(step.title)
                            .font(.system(size: 17))
                            .foregroundColor(
                                step.status == .completed ? .white :
                                    step.status == .inProgress ? .white :
                                    .white.opacity(0.5)
                            )

                        Spacer()
                    }
                    .accessibilityLabel("Step \(index + 1): \(step.title)—\(accessibilityStatus(for: step.status))")
                }
            }
            .padding(.horizontal, 32)

            // Photo upload progress (if applicable)
            if uploadService.totalCount > 0 {
                VStack(spacing: 12) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: geometry.size.width * uploadService.totalProgress, height: 4)
                                .animation(.linear(duration: 0.3), value: uploadService.totalProgress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 32)

                    Text(uploadService.uploadSummary)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 32)
            }

            Spacer()

            // Continue button (shows when ready)
            if showContinueButton {
                VStack(spacing: 16) {
                    LiquidGlassCTAButton(
                        text: "Go to Dashboard",
                        icon: "arrow.right",
                        action: onComplete,
                        isEnabled: true
                    )

                    if uploadService.isUploading {
                        Text("Photos will continue uploading in the background")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            setupPreparationSteps()
            startPreparation()
        }
    }

    private func setupPreparationSteps() {
        preparationSteps = [
            PreparationStep(title: "Creating your profile", icon: "person.circle"),
            PreparationStep(title: "Setting up your dashboard", icon: "chart.line.uptrend.xyaxis"),
            PreparationStep(title: "Configuring health sync", icon: "heart.text.square")
        ]

        if uploadService.totalCount > 0 {
            preparationSteps.append(
                PreparationStep(title: "Processing \(uploadService.totalCount) photos", icon: "photo.stack")
            )
        }
    }

    private func startPreparation() {
        Task {
            // Simulate preparation steps
            for index in preparationSteps.indices {
                withAnimation(.easeInOut(duration: 0.3)) {
                    preparationSteps[index].status = .inProgress
                    currentStepIndex = index
                }

                // Different delays for different steps
                let delay: UInt64 = index == preparationSteps.count - 1 && uploadService.totalCount > 0
                    ? 2_000_000_000  // 2 seconds for photo processing
                    : 800_000_000    // 0.8 seconds for other steps

                try? await Task.sleep(nanoseconds: delay)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    preparationSteps[index].status = .completed
                }
            }

            // Ensure minimum display time
            if !minimumLoadTime {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            withAnimation(.spring(response: 0.4)) {
                showContinueButton = true
            }
        }

        // Track minimum display time
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds minimum
            minimumLoadTime = true
        }
    }

    private func stepIcon(for index: Int) -> String {
        switch index {
        case 0: return "person.circle"
        case 1: return "chart.line.uptrend.xyaxis"
        case 2: return "heart.text.square"
        case 3: return "photo.stack"
        default: return "circle"
        }
    }

    private func accessibilityStatus(for status: StepStatus) -> String {
        switch status {
        case .pending:
            return "Not started"
        case .inProgress:
            return "In progress"
        case .completed:
            return "Completed"
        }
    }
}

#Preview {
    ProfilePreparationView(
        onboardingData: .constant(OnboardingData()),
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}
