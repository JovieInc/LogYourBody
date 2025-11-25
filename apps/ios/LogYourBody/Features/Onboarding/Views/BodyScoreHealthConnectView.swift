import SwiftUI

struct BodyScoreHealthConnectView: View {
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

    private var connectButtonOpacity: Double {
        viewModel.isRequestingHealthImport ? 0.6 : 1.0
    }

    var body: some View {
        OnboardingPageTemplate(
            title: pageTitle,
            subtitle: pageSubtitle,
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .healthConnect),
            content: {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.pink)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(cardTitle)
                                    .font(OnboardingTypography.headline)
                                    .foregroundStyle(Color.appText)

                                Text(cardSubtitle)
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }

                        if let status = viewModel.healthKitConnectionStatusText {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.green)

                                Text(status)
                                    .font(OnboardingTypography.caption)
                                    .foregroundStyle(Color.appTextSecondary)

                                Spacer()
                            }
                        }

                        Button {
                            viewModel.startHealthKitImport()
                        } label: {
                            HStack {
                                if viewModel.isRequestingHealthImport {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(connectButtonTitle)
                                    .font(.system(.headline, design: .rounded))
                            }
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .disabled(viewModel.isRequestingHealthImport)
                        .opacity(connectButtonOpacity)

                        if viewModel.isHealthKitConnected {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Adjust in Settings")
                                    .font(OnboardingTypography.caption)
                                    .foregroundStyle(Color.appPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
