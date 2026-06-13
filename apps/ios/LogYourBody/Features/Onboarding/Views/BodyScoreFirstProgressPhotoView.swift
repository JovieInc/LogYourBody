import SwiftUI

struct BodyScoreFirstProgressPhotoView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @EnvironmentObject private var authManager: AuthManager
    @State private var isAttachSheetPresented = false

    var body: some View {
        OnboardingPageTemplate(
            title: "Start your visual timeline.",
            subtitle: "Add a first progress photo now, or skip and add one from Home.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .firstPhoto),
            content: {
                VStack(alignment: .leading, spacing: 20) {
                    previewCard
                    actionStack
                }
            }
        )
        .task {
            _ = await viewModel.prepareFirstPhotoBaselineMetric()
        }
        .sheet(isPresented: $isAttachSheetPresented) {
            ProgressPhotoAttachSheet(
                targetMetric: viewModel.onboardingFirstPhotoMetric,
                fallbackDate: Date(),
                onComplete: {
                    await MainActor.run {
                        viewModel.completeFirstPhotoStep()
                    }
                }
            )
            .environmentObject(authManager)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 6) {
                Text("Photos make the timeline useful.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.appText)

                Text(
                    "We attach the photo to the baseline metrics you just entered, so Home opens with your first visual check-in."
                )
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)

                Text("Camera and photo library access are optional. You can skip this and add a photo later.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.appTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.appCard.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.appBorder.opacity(0.55), lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding_first_photo_card")
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                presentAttachSheet()
            } label: {
                if viewModel.isPreparingFirstPhotoMetric {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label("Add first photo", systemImage: "camera.fill")
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(viewModel.isPreparingFirstPhotoMetric)
            .accessibilityIdentifier("onboarding_first_photo_add_button")

            Button {
                viewModel.completeFirstPhotoStep()
            } label: {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .accessibilityIdentifier("onboarding_first_photo_continue_button")

            OnboardingTextButton(title: "Skip for now") {
                viewModel.completeFirstPhotoStep()
            }
            .accessibilityIdentifier("onboarding_first_photo_skip_button")

            if let errorMessage = viewModel.firstPhotoErrorMessage {
                Text(errorMessage)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func presentAttachSheet() {
        Task {
            guard await viewModel.prepareFirstPhotoBaselineMetric() != nil else { return }
            await MainActor.run {
                HapticManager.shared.selection()
                isAttachSheetPresented = true
            }
        }
    }
}

#Preview {
    BodyScoreFirstProgressPhotoView(
        viewModel: OnboardingFlowViewModel(includesFirstPhotoStep: true)
    )
    .environmentObject(AuthManager.shared)
    .preferredColorScheme(.dark)
}
