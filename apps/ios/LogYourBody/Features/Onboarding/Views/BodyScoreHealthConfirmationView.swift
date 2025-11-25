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
            subtitle: "Review what we imported from Apple Health.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .healthConfirmation),
            content: {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
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

                            Divider()
                                .overlay(Color.appBorder.opacity(0.4))
                        }

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

                                if metric.title != "No data" {
                                    Button {
                                        edit(metric: metric)
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Color.appPrimary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if metric.id != metrics.last?.id {
                                Divider()
                                    .overlay(Color.appBorder.opacity(0.4))
                            }
                        }
                    }

                    if let note = snapshotNote {
                        OnboardingCaptionText(text: note, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button {
                        viewModel.goToNextStep()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    OnboardingTextButton(title: "Enter manually instead") {
                        viewModel.skipHealthKit()
                    }
                }
            }
        )
    }

    private var metrics: [Metric] {
        var items: [Metric] = []

        if let heightString = formattedHeight {
            items.append(
                Metric(
                    title: "Height",
                    value: heightString,
                    subtitle: heightSubtitle,
                    icon: "ruler"
                )
            )
        }

        if let weightString = formattedWeight {
            items.append(
                Metric(
                    title: "Weight",
                    value: weightString,
                    subtitle: weightSubtitle,
                    icon: "scalemass.fill"
                )
            )
        }

        if let bodyFatString = formattedBodyFat {
            items.append(
                Metric(
                    title: "Body Fat",
                    value: bodyFatString,
                    subtitle: bodyFatSubtitle,
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
        let centimeters = viewModel.bodyScoreInput.healthSnapshot.heightCm
            ?? viewModel.bodyScoreInput.height.inCentimeters

        guard let centimeters else { return nil }

        switch preferredMeasurementSystem {
        case .metric:
            return "\(Int(round(centimeters))) cm (\(imperialHeightString(fromCentimeters: centimeters)))"
        case .imperial:
            let imperial = imperialHeightString(fromCentimeters: centimeters)
            return "\(imperial) (\(Int(round(centimeters))) cm)"
        }
    }

    private var formattedWeight: String? {
        if let kg = viewModel.bodyScoreInput.healthSnapshot.weightKg {
            return formatWeight(fromKilograms: kg)
        }

        if let stored = storedWeightValue {
            return formatWeight(value: stored, unit: preferredWeightUnit)
        }

        if let fallbackKg = viewModel.bodyScoreInput.weight.inKilograms {
            return formatWeight(fromKilograms: fallbackKg)
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

        return "We read only what you allow."
    }

    private var preferredMeasurementSystem: MeasurementSystem {
        viewModel.bodyScoreInput.measurementPreference
    }

    private var preferredWeightUnit: WeightUnit {
        viewModel.weightUnit
    }

    private var storedWeightValue: Double? {
        switch preferredWeightUnit {
        case .kilograms:
            return viewModel.bodyScoreInput.weight.inKilograms
        case .pounds:
            return viewModel.bodyScoreInput.weight.inPounds
        }
    }

    private func edit(metric: Metric) {
        switch metric.title {
        case "Height":
            viewModel.currentStep = .height
        case "Weight":
            viewModel.currentStep = .manualWeight
        case "Body Fat":
            viewModel.currentStep = .bodyFatChoice
        default:
            break
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var heightSubtitle: String {
        if let date = viewModel.bodyScoreInput.healthSnapshot.heightDate {
            return "Last measured \(relativeDateString(from: date))"
        }
        if viewModel.bodyScoreInput.healthSnapshot.heightCm != nil {
            return "From Apple Health"
        }
        return "From your profile"
    }

    private var weightSubtitle: String {
        if let date = viewModel.bodyScoreInput.healthSnapshot.weightDate {
            return "Last logged \(relativeDateString(from: date))"
        }
        if viewModel.bodyScoreInput.healthSnapshot.weightKg != nil {
            return "From Apple Health"
        }
        return "From your profile"
    }

    private var bodyFatSubtitle: String {
        if let date = viewModel.bodyScoreInput.healthSnapshot.bodyFatDate {
            return "Last logged \(relativeDateString(from: date))"
        }
        if viewModel.bodyScoreInput.healthSnapshot.bodyFatPercentage != nil {
            return "Imported from Health"
        }
        return "From your estimate"
    }

    private func imperialHeightString(fromCentimeters centimeters: Double) -> String {
        let inchesTotal = centimeters / 2.54
        let feet = Int(inchesTotal) / 12
        let inches = Int(round(inchesTotal)) % 12
        return "\(feet)' \(inches)\""
    }

    private func formatWeight(fromKilograms kilograms: Double) -> String {
        switch preferredWeightUnit {
        case .kilograms:
            return formatWeight(value: kilograms, unit: .kilograms)
        case .pounds:
            return formatWeight(value: kilograms * 2.2046226218, unit: .pounds)
        }
    }

    private func formatWeight(value: Double, unit: WeightUnit) -> String {
        let rounded = value.rounded()
        switch unit {
        case .kilograms:
            return String(format: "%.0f kg", rounded)
        case .pounds:
            return String(format: "%.0f lbs", rounded)
        }
    }
}

#Preview {
    BodyScoreHealthConfirmationView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
