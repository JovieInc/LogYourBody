import SwiftUI

@MainActor
final class OnboardingFlowViewModel: ObservableObject {
    enum Step: Hashable {
        case hook
        case basics
        case height
        case healthConnect
        case manualWeight
        case bodyFatKnowledge
        case bodyFatNumeric
        case bodyFatVisual
        case loading
        case score
        case account
        case paywall
    }

    struct HealthImportSummary: Equatable {
        var heightInches: Double?
        var weightPounds: Double?
        var bodyFatPercentage: Double?
    }

    struct VisualEstimate: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let rangeLabel: String
        let estimatedValue: Double
    }

    @Published var path: [Step] = []
    @Published var sex: BodyScoreCalculator.Input.Sex = .male
    @Published var birthYear: Int = Calendar.current.component(.year, from: Date()) - 30

    @Published var heightUnit: UnitToggleRow.Unit = .imperial
    @Published var heightFeet: Int = 5
    @Published var heightInches: Int = 10
    @Published var heightCentimeters: Double = 178

    @Published var weightUnitImperial = true
    @Published var weightValue: Double = 180

    @Published var bodyFatPercentage: Double?
    @Published var selectedVisualEstimate: VisualEstimate?

    @Published var healthSummary: HealthImportSummary?
    @Published var didConnectHealthKit = false
    @Published var isRequestingHealthKit = false

    @Published var isCalculatingScore = false
    @Published var bodyScoreResult: BodyScoreCalculator.Result?

    @Published var emailAddress: String = ""
    @Published var isSendingEmail = false
    @Published var emailSent = false

    @Published var showEmailSheet = false

    private let healthKitManager = HealthKitManager.shared
    private let calculator = BodyScoreCalculator()

    var yearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let start = currentYear - 80
        let end = currentYear - 18
        return Array((start...end).reversed())
    }

    var visualOptions: [VisualEstimate] {
        if sex == .female {
            return [
                .init(title: "Very lean", rangeLabel: "16–19%", estimatedValue: 17.5),
                .init(title: "Lean", rangeLabel: "20–23%", estimatedValue: 21.5),
                .init(title: "Fit", rangeLabel: "24–27%", estimatedValue: 25.5),
                .init(title: "Average", rangeLabel: "28–32%", estimatedValue: 30),
                .init(title: "Soft", rangeLabel: "33–38%", estimatedValue: 35.5),
                .init(title: "Above 38%", rangeLabel: "39%+", estimatedValue: 40)
            ]
        }
        return [
            .init(title: "Very lean", rangeLabel: "6–9%", estimatedValue: 7.5),
            .init(title: "Lean", rangeLabel: "10–13%", estimatedValue: 11.5),
            .init(title: "Fit", rangeLabel: "14–17%", estimatedValue: 15.5),
            .init(title: "Average", rangeLabel: "18–22%", estimatedValue: 20),
            .init(title: "Soft", rangeLabel: "23–27%", estimatedValue: 25),
            .init(title: "Over 28%", rangeLabel: "28%+", estimatedValue: 30)
        ]
    }

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        birthYear = currentYear - 30
    }

    func start() {
        path = [.basics]
    }

    func goToHeight() {
        path.append(.height)
    }

    func goToHealthConnect() {
        path.append(.healthConnect)
    }

    func goToManualWeightIfNeeded() {
        if healthSummary?.weightPounds != nil {
            goToBodyFatKnowledge()
        } else {
            path.append(.manualWeight)
        }
    }

    func editImportedMetrics() {
        healthSummary = nil
        path.append(.manualWeight)
    }

    func goToBodyFatKnowledge() {
        path.append(.bodyFatKnowledge)
    }

    func goToBodyFatNumeric() {
        path.append(.bodyFatNumeric)
    }

    func goToBodyFatVisual() {
        path.append(.bodyFatVisual)
    }

    func skipToScore() {
        guard let input = scoreInput else { return }
        isCalculatingScore = true
        bodyScoreResult = nil
        path.append(.loading)

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let result = calculator.calculate(input: input)
            await MainActor.run {
                self.bodyScoreResult = result
                self.isCalculatingScore = false
                if let loadingIndex = self.path.firstIndex(of: .loading) {
                    self.path.removeSubrange(loadingIndex..<self.path.count)
                }
                self.path.append(.score)
            }
        }
    }

    func connectHealthKit() async {
        isRequestingHealthKit = true
        defer { isRequestingHealthKit = false }
        let success = await healthKitManager.requestAuthorization()
        guard success else { return }
        didConnectHealthKit = true

        async let height = try? await healthKitManager.fetchHeight()
        async let weight = try? await healthKitManager.fetchLatestWeight()
        async let bodyFat = try? await healthKitManager.fetchLatestBodyFatPercentage()

        let fetchedHeight = await height ?? nil
        let fetchedWeight = await weight
        let fetchedBodyFat = await bodyFat

        await MainActor.run {
            let summary = HealthImportSummary(
                heightInches: fetchedHeight,
                weightPounds: fetchedWeight?.weight,
                bodyFatPercentage: fetchedBodyFat?.percentage
            )
            self.healthSummary = summary

            if let inches = summary.heightInches {
                self.heightUnit = .imperial
                self.heightFeet = Int(inches) / 12
                self.heightInches = Int(inches) % 12
                self.heightCentimeters = inches * 2.54
            }
            if let weight = summary.weightPounds {
                self.weightValue = weight
                self.weightUnitImperial = true
            }
            if let bf = summary.bodyFatPercentage {
                self.bodyFatPercentage = bf
            }
        }
    }

    func confirmHealthImport() {
        goToBodyFatKnowledge()
    }

    func prepareScoreCalculation() {
        guard scoreInput != nil else { return }
        skipToScore()
    }

    func prepareAccountCreation() {
        path.append(.account)
    }

    func proceedToPaywall() {
        if !path.contains(.paywall) {
            path.append(.paywall)
        }
    }

    func sendEmailReport() async {
        guard !emailAddress.isEmpty, let result = bodyScoreResult else { return }
        isSendingEmail = true
        defer { isSendingEmail = false }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        // Placeholder for backend integration. Store minimal data for analytics.
        let payload = "Email: \(emailAddress) Score: \(result.score)"
        print(payload)
        emailSent = true
    }

    func resetEmailState() {
        emailSent = false
        emailAddress = ""
    }

    var shareText: String {
        guard let result = bodyScoreResult else { return "" }
        return "Body Score \(result.scoreDisplay) — \(result.tagline) • Leaner than \(result.leanPercentile)% of people your age."
    }

    var scoreInput: BodyScoreCalculator.Input? {
        guard let bodyFat = resolvedBodyFat else { return nil }
        return BodyScoreCalculator.Input(
            sex: sex,
            birthYear: birthYear,
            heightInches: resolvedHeightInches,
            weightPounds: resolvedWeightPounds,
            bodyFatPercentage: bodyFat
        )
    }

    private var resolvedBodyFat: Double? {
        if let value = bodyFatPercentage { return value }
        return selectedVisualEstimate?.estimatedValue
    }

    private var resolvedHeightInches: Double {
        switch heightUnit {
        case .imperial:
            return Double((heightFeet * 12) + heightInches)
        case .metric:
            return heightCentimeters / 2.54
        }
    }

    private var resolvedWeightPounds: Double {
        weightUnitImperial ? weightValue : weightValue * 2.20462
    }
}

extension OnboardingFlowViewModel.HealthImportSummary {
    var displayRows: [String] {
        var rows: [String] = []
        if let heightInches {
            let feet = Int(heightInches) / 12
            let inches = Int(round(heightInches)) % 12
            rows.append("Height: \(feet)′\(inches)″")
        }
        if let weightPounds {
            rows.append(String(format: "Latest weight: %.0f lb", weightPounds))
        }
        if let bodyFatPercentage {
            rows.append(String(format: "Body fat: %.1f%%", bodyFatPercentage))
        }
        return rows
    }
}
