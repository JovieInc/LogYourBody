import SwiftUI

enum HealthConfirmationDisplayPolicy {
    enum Source: Equatable {
        case healthKit
        case entered
        case scan
        case visualEstimate
        case unknown
    }

    struct ResolvedMetric: Equatable {
        let value: Double
        let source: Source
        let date: Date?
    }

    /// Explicit entries override older Health snapshots; legacy inputs without
    /// provenance retain snapshot priority. The value uses the requested unit.
    static func weight(
        input: BodyScoreInput, preferredUnit: WeightUnit = .kilograms
    ) -> ResolvedMetric? {
        let stored = preferredUnit == .kilograms ? input.weight.inKilograms : input.weight.inPounds
        if let stored {
            switch input.weightSource {
            case .manual:
                return ResolvedMetric(value: stored, source: .entered, date: nil)
            case .scan:
                return ResolvedMetric(value: stored, source: .scan, date: nil)
            case .healthKit, nil:
                break
            }
        }
        if let kilograms = input.healthSnapshot.weightKg {
            let value = preferredUnit == .kilograms ? kilograms : kilograms * 2.2046226218
            return ResolvedMetric(value: value, source: .healthKit, date: input.healthSnapshot.weightDate)
        }
        guard let stored else { return nil }
        let source: Source = input.weightSource == .healthKit ? .healthKit : .unknown
        return ResolvedMetric(value: stored, source: source, date: nil)
    }

    static func bodyFat(input: BodyScoreInput) -> ResolvedMetric? {
        if let percentage = input.bodyFat.percentage {
            switch input.bodyFat.source {
            case .manualValue:
                return ResolvedMetric(value: percentage, source: .entered, date: nil)
            case .scan:
                return ResolvedMetric(value: percentage, source: .scan, date: nil)
            case .visualEstimate:
                return ResolvedMetric(value: percentage, source: .visualEstimate, date: nil)
            case .healthKit, .unspecified:
                break
            }
        }
        if let percentage = input.healthSnapshot.bodyFatPercentage {
            return ResolvedMetric(value: percentage, source: .healthKit, date: input.healthSnapshot.bodyFatDate)
        }
        guard let percentage = input.bodyFat.percentage else { return nil }
        let source: Source = input.bodyFat.source == .healthKit ? .healthKit : .unknown
        return ResolvedMetric(value: percentage, source: source, date: nil)
    }

    static func sourceText(for metric: ResolvedMetric, now: Date = Date()) -> String {
        switch metric.source {
        case .healthKit:
            guard let date = metric.date else { return "From Apple Health" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: date, relativeTo: now)
            return "From Apple Health · Last logged \(relativeDate)"
        case .entered:
            return "Entered by you"
        case .scan:
            return "From your scan"
        case .visualEstimate:
            return "Visual estimate"
        case .unknown:
            return "Source not recorded"
        }
    }

    /// Renders a centimeter height as feet/inches, e.g. 178 cm → 5' 10".
    static func imperialHeightString(fromCentimeters centimeters: Double) -> String {
        guard centimeters > 0, HeightEntryPolicy.isRepresentableCentimeters(centimeters),
              let inchesTotal = Int(exactly: (centimeters / 2.54).rounded()) else { return "—" }
        let feet = inchesTotal / 12
        let inches = inchesTotal % 12
        return "\(feet)' \(inches)\""
    }

    /// Shows the preferred unit first with the converted value in parentheses.
    static func formattedHeight(centimeters: Double, system: MeasurementSystem) -> String {
        guard centimeters > 0, HeightEntryPolicy.isRepresentableCentimeters(centimeters),
              let roundedCentimeters = Int(exactly: centimeters.rounded()) else { return "—" }
        switch system {
        case .metric:
            return "\(roundedCentimeters) cm (\(imperialHeightString(fromCentimeters: centimeters)))"
        case .imperial:
            let imperial = imperialHeightString(fromCentimeters: centimeters)
            return "\(imperial) (\(roundedCentimeters) cm)"
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

    static func preferredWeightString(input: BodyScoreInput, preferredUnit: WeightUnit) -> String? {
        guard let metric = weight(input: input, preferredUnit: preferredUnit) else { return nil }
        return formatWeight(value: metric.value, unit: preferredUnit)
    }

    /// Health-imported height wins over the stored entry; nil when neither exists.
    static func preferredHeightString(input: BodyScoreInput, system: MeasurementSystem) -> String? {
        let centimeters = input.healthSnapshot.heightCm ?? input.height.inCentimeters
        guard let centimeters, centimeters > 0,
              HeightEntryPolicy.isRepresentableCentimeters(centimeters) else { return nil }
        return formattedHeight(centimeters: centimeters, system: system)
    }

    static func preferredBodyFatString(input: BodyScoreInput) -> String? {
        guard let metric = bodyFat(input: input) else { return nil }
        return String(format: "%.1f%%", metric.value)
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
            title: "Here’s what we found.",
            subtitle: "Review the measurements we’ll use for your body composition.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .healthConfirmation),
            screen: .confirmImportedData,
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

        if let weight = HealthConfirmationDisplayPolicy.weight(
            input: viewModel.bodyScoreInput, preferredUnit: preferredWeightUnit
        ) {
            items.append(
                Metric(
                    title: "Weight",
                    value: HealthConfirmationDisplayPolicy.formatWeight(
                        value: weight.value, unit: preferredWeightUnit
                    ),
                    subtitle: HealthConfirmationDisplayPolicy.sourceText(for: weight),
                    icon: "scalemass.fill"
                )
            )
        }

        if let bodyFat = HealthConfirmationDisplayPolicy.bodyFat(input: viewModel.bodyScoreInput) {
            items.append(
                Metric(
                    title: "Body Fat",
                    value: String(format: "%.1f%%", bodyFat.value),
                    subtitle: HealthConfirmationDisplayPolicy.sourceText(for: bodyFat),
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
}

#Preview {
    BodyScoreHealthConfirmationView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
