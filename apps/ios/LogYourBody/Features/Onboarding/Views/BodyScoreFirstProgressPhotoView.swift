import SwiftUI

struct BodyScoreFirstProgressPhotoView: View {
    @Environment(\.theme)
    private var theme

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
                    await viewModel.completeFirstPhotoStep()
                }
            )
            .environmentObject(authManager)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.colors.text.opacity(0.82))

            VStack(alignment: .leading, spacing: 6) {
                Text("Photos make the timeline useful.")
                    .font(theme.typography.headlineSmall)
                    .foregroundStyle(theme.colors.text)

                Text(
                    "We attach the photo to the baseline metrics you just entered, so Home opens with your first visual check-in."
                )
                    .font(OnboardingTypography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(theme.colors.text)

                Text("Camera and photo library access are optional. You choose what to add, and can skip this for now.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: 22,
            tint: theme.colors.text,
            tintOpacity: 0.04,
            borderColor: theme.colors.border,
            borderOpacity: 0.65,
            shadowOpacity: 0.12,
            shadowRadius: 12,
            shadowY: 6
        )
        .accessibilityIdentifier("onboarding_first_photo_card")
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                presentAttachSheet()
            } label: {
                if viewModel.isPreparingFirstPhotoMetric || viewModel.isCompletingOnboarding {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label("Add first photo", systemImage: "camera.fill")
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(viewModel.isPreparingFirstPhotoMetric || viewModel.isCompletingOnboarding)
            .accessibilityIdentifier("onboarding_first_photo_add_button")

            Button {
                Task {
                    await viewModel.completeFirstPhotoStep()
                }
            } label: {
                if viewModel.isCompletingOnboarding {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.appTextSecondary))
                } else {
                    Text("Skip for now")
                }
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .disabled(viewModel.isCompletingOnboarding)
            .accessibilityIdentifier("onboarding_first_photo_skip_button")

                Text("You can add progress photos later from Home.")
                    .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let errorMessage = viewModel.firstPhotoErrorMessage {
                Text(errorMessage)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.error)
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
