import SwiftUI

struct BodyScoreHealthConfirmationView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private struct Metric: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let subtitle: String
        let icon: String
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Health data synced",
            subtitle: "We grabbed the latest stats from Apple Health. Confirm or edit anything before continuing.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 24) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(metrics) { metric in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: metric.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(metric.title.uppercased())
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(Color.appTextSecondary)

                                    Text(metric.value)
                                        .font(.system(.title2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Color.appText)

                                    Text(metric.subtitle)
                                        .font(OnboardingTypography.body)
                                        .foregroundStyle(Color.appTextSecondary)
                                }

                                Spacer()
                            }

                            if metric.id != metrics.last?.id {
                                Divider()
                                    .overlay(Color.appBorder.opacity(0.4))
                            }
                        }
                    }
                }

                if let note = snapshotNote {
                    OnboardingCaptionText(text: note, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            VStack(spacing: 12) {
                Button("Looks good") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("I'd rather enter manually") {
                    viewModel.skipHealthKit()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var metrics: [Metric] {
        var items: [Metric] = []

        if let heightString = formattedHeight {
            items.append(
                Metric(
                    title: "Height",
                    value: heightString,
                    subtitle: "From Health",
                    icon: "ruler"
                )
            )
        }

        if let weightString = formattedWeight {
            items.append(
                Metric(
                    title: "Weight",
                    value: weightString,
                    subtitle: "Last logged weight",
                    icon: "figure.scale"
                )
            )
        }

        if let bodyFatString = formattedBodyFat {
            items.append(
                Metric(
                    title: "Body Fat",
                    value: bodyFatString,
                    subtitle: "Imported from Health",
                    icon: "percent"
                )
            )
        }

        if items.isEmpty {
            items.append(
                Metric(
                    title: "No data",
                    value: "We'll collect it manually",
                    subtitle: "Apple Health didn't share anything this time.",
                    icon: "exclamationmark.triangle"
                )
            )
        }

        return items
    }

    private var formattedHeight: String? {
        guard let centimeters = viewModel.bodyScoreInput.healthSnapshot.heightCm else { return nil }
        let inches = centimeters / 2.54
        let feet = Int(inches) / 12
        let remainingInches = Int(round(inches)) % 12
        return "\(feet)' \(remainingInches)\" (\(Int(round(centimeters))) cm)"
    }

    private var formattedWeight: String? {
        if let kg = viewModel.bodyScoreInput.healthSnapshot.weightKg {
            let pounds = kg * 2.2046226218
            return String(format: "%.0f lbs", pounds)
        }

        if let pounds = viewModel.bodyScoreInput.weight.inPounds {
            return String(format: "%.0f lbs", pounds)
        }

        return nil
    }

    private var formattedBodyFat: String? {
        if let percentage = viewModel.bodyScoreInput.healthSnapshot.bodyFatPercentage {
            return String(format: "%.1f%%", percentage)
        }

        if let percentage = viewModel.bodyScoreInput.bodyFat.percentage {
            return String(format: "%.1f%%", percentage)
        }

        return nil
    }

    private var snapshotNote: String? {
        guard viewModel.bodyScoreInput.healthSnapshot.hasAnyValue else {
            return nil
        }

        return "You can update these anytime from Apple Health. We only read what you allow."
    }
}

#Preview {
    BodyScoreHealthConfirmationView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
