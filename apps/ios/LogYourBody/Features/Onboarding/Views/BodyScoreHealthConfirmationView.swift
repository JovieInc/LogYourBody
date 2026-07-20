import SwiftUI

enum HealthConfirmationDisplayPolicy {
    /// Renders a centimeter height as feet/inches, e.g. 178 cm → 5' 10".
    static func imperialHeightString(fromCentimeters centimeters: Double) -> String {
        let inchesTotal = centimeters / 2.54
        let feet = Int(inchesTotal) / 12
        let inches = Int(round(inchesTotal)) % 12
        return "\(feet)' \(inches)\""
    }

    /// Shows the preferred unit first with the converted value in parentheses.
    static func formattedHeight(centimeters: Double, system: MeasurementSystem) -> String {
        switch system {
        case .metric:
            return "\(Int(round(centimeters))) cm (\(imperialHeightString(fromCentimeters: centimeters)))"
        case .imperial:
            let imperial = imperialHeightString(fromCentimeters: centimeters)
            return "\(imperial) (\(Int(round(centimeters))) cm)"
        }
    }

    /// Whole-number weight display in the requested unit.
    static func formatWeight(value: Double, unit: WeightUnit) -> String {
        let rounded = value.rounded()
        switch unit {
        case .kilograms:
            return String(format: "%.0f kg", rounded)
        case .pounds:
            return String(format: "%.0f lbs", rounded)
        }
    }

    static func formatWeight(fromKilograms kilograms: Double, unit: WeightUnit) -> String {
        switch unit {
        case .kilograms:
            return formatWeight(value: kilograms, unit: .kilograms)
        case .pounds:
            return formatWeight(value: kilograms * 2.2046226218, unit: .pounds)
        }
    }

    /// Health-imported values win over the stored entry; nil when neither exists.
    static func preferredWeightString(input: BodyScoreInput, preferredUnit: WeightUnit) -> String? {
        if let kilograms = input.healthSnapshot.weightKg {
            return formatWeight(fromKilograms: kilograms, unit: preferredUnit)
        }

        let stored: Double?
        switch preferredUnit {
        case .kilograms:
            stored = input.weight.inKilograms
        case .pounds:
            stored = input.weight.inPounds
        }

        if let stored {
            return formatWeight(value: stored, unit: preferredUnit)
        }

        if let fallbackKilograms = input.weight.inKilograms {
            return formatWeight(fromKilograms: fallbackKilograms, unit: preferredUnit)
        }

        return nil
    }

    /// Health-imported height wins over the stored entry; nil when neither exists.
    static func preferredHeightString(input: BodyScoreInput, system: MeasurementSystem) -> String? {
        let centimeters = input.healthSnapshot.heightCm ?? input.height.inCentimeters
        guard let centimeters else { return nil }
        return formattedHeight(centimeters: centimeters, system: system)
    }

    /// Health-imported body fat wins over the manual estimate; nil when neither exists.
    static func preferredBodyFatString(input: BodyScoreInput) -> String? {
        if let percentage = input.healthSnapshot.bodyFatPercentage {
            return String(format: "%.1f%%", percentage)
        }

        if let percentage = input.bodyFat.percentage {
            return String(format: "%.1f%%", percentage)
        }

        return nil
    }
}

struct BodyScoreHealthConfirmationView: View {
    @Environment(\.theme)
    private var theme

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
                VStack(spacing: JovieTokens.sectionGap) {
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 16) {
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

                                Divider()
                                    .overlay(theme.colors.border.opacity(0.65))
                            }

                            ForEach(metrics) { metric in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: metric.icon)
                                        .font(.system(.title3, design: .rounded).weight(.semibold))
                                        .foregroundStyle(theme.colors.primary)
                                        .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(metric.title.uppercased())
                                            .font(OnboardingTypography.caption)
                                            .foregroundStyle(theme.colors.textSecondary)

                                        Text(metric.value)
                                            .font(theme.typography.headlineLarge)
                                            .foregroundStyle(theme.colors.text)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text(metric.subtitle)
                                            .font(OnboardingTypography.body)
                                            .foregroundStyle(theme.colors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    if metric.title != "No data" {
                                        Button {
                                            edit(metric: metric)
                                        } label: {
                                            Image(systemName: "square.and.pencil")
                                                .font(.system(.body, design: .default).weight(.medium))
                                                .foregroundStyle(theme.colors.primary)
                                                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Edit \(metric.title)")
                                    }
                                }

                                if metric.id != metrics.last?.id {
                                    Divider()
                                        .overlay(theme.colors.border.opacity(0.65))
                                }
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
        HealthConfirmationDisplayPolicy.preferredHeightString(
            input: viewModel.bodyScoreInput,
            system: preferredMeasurementSystem
        )
    }

    private var formattedWeight: String? {
        HealthConfirmationDisplayPolicy.preferredWeightString(
            input: viewModel.bodyScoreInput,
            preferredUnit: preferredWeightUnit
        )
    }

    private var formattedBodyFat: String? {
        HealthConfirmationDisplayPolicy.preferredBodyFatString(input: viewModel.bodyScoreInput)
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
}

#Preview {
    BodyScoreHealthConfirmationView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
