import SwiftUI

struct BodyScoreHealthConnectView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private var cardTitle: String {
        viewModel.isHealthKitConnected ? "Apple Health connected" : "Sync Apple Health"
    }

    private var cardSubtitle: String {
        if viewModel.isHealthKitConnected {
            return "We'll keep height, weight, and body fat in sync."
        }
        return "We only read the basics–never share without consent."
    }

    private var connectButtonTitle: String {
        viewModel.isRequestingHealthImport ? "Connecting…" : "Connect Apple Health"
    }

    private var connectButtonOpacity: Double {
        viewModel.isRequestingHealthImport ? 0.6 : 1.0
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Pull from Apple Health?",
            subtitle: "Auto-fill weight, body fat, and height. Quick and private.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .healthConnect),
            content: {
                VStack(spacing: 24) {
                    OnboardingCard {
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

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "ruler")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.appPrimary)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Height")
                                            .font(OnboardingTypography.caption)
                                            .foregroundStyle(Color.appTextSecondary)

                                        Text("Read from Apple Health for your profile.")
                                            .font(OnboardingTypography.body)
                                            .foregroundStyle(Color.appText)
                                    }
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "figure.scale")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.appPrimary)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Weight")
                                            .font(OnboardingTypography.caption)
                                            .foregroundStyle(Color.appTextSecondary)

                                        Text("Read & write with your permission.")
                                            .font(OnboardingTypography.body)
                                            .foregroundStyle(Color.appText)
                                    }
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "percent")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.appPrimary)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Body fat")
                                            .font(OnboardingTypography.caption)
                                            .foregroundStyle(Color.appTextSecondary)

                                        Text("Read & write with your permission.")
                                            .font(OnboardingTypography.body)
                                            .foregroundStyle(Color.appText)
                                    }
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

                            OnboardingCaptionText(text: "Only stored locally unless you opt in to sync.", alignment: .leading)

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
                    }

                    Button {
                        viewModel.skipHealthKit()
                    } label: {
                        VStack(spacing: 8) {
                            Text("Enter manually instead")
                                .font(OnboardingTypography.headline)
                                .foregroundStyle(Color.appText)
                            OnboardingCaptionText(text: "Takes about 30 seconds.", alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.appCard.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.appBorder.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }
}

#Preview {
    BodyScoreHealthConnectView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
