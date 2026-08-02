import SwiftUI

enum OnboardingFirstPhotoAction: Equatable {
    case add
    case skip
}

struct OnboardingFirstPhotoActionState: Equatable {
    let isBusy: Bool
    let activeAction: OnboardingFirstPhotoAction?

    var disablesActions: Bool {
        isBusy || activeAction != nil
    }

    func showsLoader(for action: OnboardingFirstPhotoAction) -> Bool {
        activeAction == action
    }
}

struct BodyScoreFirstProgressPhotoView: View {
    @Environment(\.theme)
    private var theme

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @EnvironmentObject private var authManager: AuthManager
    @State private var isAttachSheetPresented = false
    @State private var activeAction: OnboardingFirstPhotoAction?

    private var actionState: OnboardingFirstPhotoActionState {
        OnboardingFirstPhotoActionState(
            isBusy: viewModel.isPreparingFirstPhotoMetric || viewModel.isCompletingOnboarding,
            activeAction: activeAction
        )
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Start your visual timeline.",
            subtitle: "Add a photo now, or do it later from Home.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .firstPhoto),
            content: {
                VStack(alignment: .leading, spacing: theme.spacing.lg) {
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
                    await completeFirstPhotoStep(from: .add)
                }
            )
            .environmentObject(authManager)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Image(systemName: "camera.metering.center.weighted")
                .font(theme.typography.headlineMedium)
                .foregroundStyle(theme.colors.text.opacity(0.82))

            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text("Start with a photo.")
                    .font(theme.typography.headlineSmall)
                    .foregroundStyle(theme.colors.text)

                Text("We’ll pair it with the baseline metrics you just entered, so Home starts with a visual check-in.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: theme.spacing.sm) {
                Image(systemName: "lock.shield")
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(theme.colors.text)

                Text("Camera and photo library access are optional.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: theme.radius.card,
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
        VStack(spacing: theme.spacing.sm) {
            Button {
                presentAttachSheet()
            } label: {
                if actionState.showsLoader(for: .add) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label("Add first photo", systemImage: "camera.fill")
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(actionState.disablesActions)
            .accessibilityIdentifier("onboarding_first_photo_add_button")

            Button {
                Task {
                    await completeFirstPhotoStep(from: .skip)
                }
            } label: {
                if actionState.showsLoader(for: .skip) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.appTextSecondary))
                } else {
                    Text("Skip for now")
                }
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .disabled(actionState.disablesActions)
            .accessibilityIdentifier("onboarding_first_photo_skip_button")

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
            activeAction = .add
            defer { activeAction = nil }
            guard await viewModel.prepareFirstPhotoBaselineMetric() != nil else { return }
            await MainActor.run {
                HapticManager.shared.selection()
                isAttachSheetPresented = true
            }
        }
    }

    private func completeFirstPhotoStep(from action: OnboardingFirstPhotoAction) async {
        activeAction = action
        defer { activeAction = nil }
        await viewModel.completeFirstPhotoStep()
    }
}

#Preview {
    BodyScoreFirstProgressPhotoView(
        viewModel: OnboardingFlowViewModel(includesFirstPhotoStep: true)
    )
    .environmentObject(AuthManager.shared)
    .preferredColorScheme(.dark)
}
