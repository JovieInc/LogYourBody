import SwiftUI

struct BodyScoreHealthConnectView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.openURL)
    private var openURL

    @ObservedObject var viewModel: OnboardingFlowViewModel

    private var pageTitle: String {
        viewModel.isHealthKitConnected ? "Apple Health is connected" : "Pull from Apple Health?"
    }

    private var pageSubtitle: String {
        if viewModel.isHealthKitConnected {
            return "Using your latest height, weight, and body fat from Apple Health."
        }
        return "Pull recent height, weight, and body fat from Apple Health."
    }

    private var cardTitle: String {
        viewModel.isHealthKitConnected ? "Apple Health connected" : "Sync Apple Health"
    }

    private var cardSubtitle: String {
        if viewModel.isHealthKitConnected {
            return "Keeps height, weight, and body fat in sync."
        }
        return "Reads only the basics you allow. You stay in control."
    }

    private var connectButtonTitle: String {
        if viewModel.isRequestingHealthImport {
            return "Connecting…"
        }
        if viewModel.isHealthKitConnected {
            return "Continue"
        }
        return "Connect Apple Health"
    }

    var body: some View {
        OnboardingPageTemplate(
            title: pageTitle,
            subtitle: pageSubtitle,
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .healthConnect),
            content: {
                VStack(spacing: JovieTokens.sectionGap) {
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "heart.text.square")
                                    .font(.system(.title2, design: .rounded).weight(.semibold))
                                    .foregroundStyle(theme.colors.accentPink)
                                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cardTitle)
                                        .font(OnboardingTypography.headline)
                                        .foregroundStyle(theme.colors.text)

                                    Text(cardSubtitle)
                                        .font(OnboardingTypography.body)
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if let status = viewModel.healthKitConnectionStatusText {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(.body, design: .default).weight(.semibold))
                                        .foregroundStyle(theme.colors.success)

                                    Text(status)
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)

                                    Spacer()
                                }
                                .accessibilityLabel("Apple Health status: \(status)")
                            }

                            if viewModel.isHealthKitConnected {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                } label: {
                                    Text("Adjust in Settings")
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(theme.colors.primary)
                                }
                                .buttonStyle(.plain)
                                .jovieTouchTarget()
                                .accessibilityHint("Opens the app’s Settings page.")
                            }
                        }
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button {
                        viewModel.startHealthKitImport()
                    } label: {
                        HStack {
                            if viewModel.isRequestingHealthImport {
                                ProgressView()
                                    .tint(theme.colors.background)
                            }
                            Text(connectButtonTitle)
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.isRequestingHealthImport)
                    .accessibilityLabel(connectButtonTitle)

                    OnboardingTextButton(title: "Enter manually instead") {
                        viewModel.skipHealthKit()
                    }
                }
            }
        )
    }
}

#Preview {
    BodyScoreHealthConnectView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
