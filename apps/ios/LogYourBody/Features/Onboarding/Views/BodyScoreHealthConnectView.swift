import SwiftUI

struct BodyScoreHealthConnectView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingPageTemplate(
            title: "Pull from Apple Health?",
            subtitle: "Auto-fill weight, body fat, and height. Quick and private.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 24) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.pink)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sync Apple Health")
                                    .font(OnboardingTypography.headline)
                                    .foregroundStyle(Color.appText)

                                Text("We only read the basics—never share without consent.")
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(Color.appTextSecondary)
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
                                Text(viewModel.isRequestingHealthImport ? "Connecting" : "Connect to Health")
                                    .font(.system(.headline, design: .rounded))
                            }
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .disabled(viewModel.isRequestingHealthImport)
                        .opacity(viewModel.isRequestingHealthImport ? 0.7 : 1)

                        OnboardingCaptionText(text: "Only stored locally unless you opt in to sync.", alignment: .leading)
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
    }
}

#Preview {
    BodyScoreHealthConnectView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
