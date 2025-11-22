import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Hero Card

    func heroCard(metric: BodyMetrics) -> some View {
        let bodyScore = bodyScoreText()
        return DashboardBodyScoreHeroCard(
            score: bodyScore.score,
            scoreText: bodyScore.scoreText,
            tagline: bodyScore.tagline,
            ffmiValue: heroFFMIValue(),
            ffmiCaption: heroFFMICaption(),
            bodyFatValue: heroBodyFatValue(),
            bodyFatCaption: heroBodyFatCaption(),
            weightValue: heroWeightValue(),
            weightCaption: heroWeightCaption(),
            deltaText: heroBodyScoreDeltaText(),
            onTapFFMI: {
                selectedMetricType = .ffmi
                isMetricDetailActive = true
            },
            onTapBodyFat: {
                selectedMetricType = .bodyFat
                isMetricDetailActive = true
            },
            onTapWeight: {
                selectedMetricType = .weight
                isMetricDetailActive = true
            }
        )
    }

    func bodyScoreText() -> (score: Int, scoreText: String, tagline: String) {
        _ = bodyScoreRefreshToken
        let hasHeight = authManager.currentUser?.profile?.height != nil

        if let dynamic = dynamicBodyScoreResult() {
            return (dynamic.score, "\(dynamic.score)", dynamic.statusTagline)
        }

        if hasHeight, let result = latestBodyScoreResult() {
            return (result.score, "\(result.score)", result.statusTagline)
        }

        let missingTagline = hasHeight ? "Complete onboarding to unlock" : "Add your height to unlock"
        return (0, "--", missingTagline)
    }

    func heroFFMIValue() -> String {
        if let metric = currentMetric {
            let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
            )

            if let ffmiData = MetricsInterpolationService.shared.estimateFFMI(
                for: metric.date,
                metrics: bodyMetrics,
                heightInches: heightInches
            ) {
                return String(format: "%.1f", ffmiData.value)
            }
        }

        if let result = latestBodyScoreResult() {
            return String(format: "%.1f", result.ffmi)
        }

        return "--"
    }

    func heroFFMICaption() -> String {
        if let metric = currentMetric {
            let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
            )

            if let heightInches,
               let ffmiData = MetricsInterpolationService.shared.estimateFFMI(
                   for: metric.date,
                   metrics: bodyMetrics,
                   heightInches: heightInches
               ) {
                let genderString = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
                let isFemale = genderString.contains("female") || genderString.contains("woman")
                let sex: BiologicalSex = isFemale ? .female : .male
                return descriptiveHeroFFMIStatus(ffmiData.value, sex: sex)
            }
        }

        if let result = latestBodyScoreResult() {
            return result.ffmiStatus
        }

        return "FFMI"
    }

    private func descriptiveHeroFFMIStatus(_ ffmi: Double, sex: BiologicalSex) -> String {
        switch sex {
        case .male:
            switch ffmi {
            case ..<18:
                return "Developing"
            case 18..<20:
                return "Solid base"
            case 20..<22.5:
                return "Athletic"
            case 22.5..<25:
                return "Advanced"
            default:
                return "Elite"
            }
        case .female:
            switch ffmi {
            case ..<13:
                return "Developing"
            case 13..<15:
                return "Solid base"
            case 15..<17:
                return "Athletic"
            case 17..<19:
                return "Advanced"
            default:
                return "Elite"
            }
        }
    }

    func heroBodyFatValue() -> String {
        formatBodyFatValue(currentMetric?.bodyFatPercentage)
    }

    func heroBodyFatCaption() -> String {
        "%"
    }

    func heroWeightValue() -> String {
        formatWeightValue(currentMetric?.weight)
    }

    func heroWeightCaption() -> String {
        weightUnit
    }

    func latestBodyScoreResult() -> BodyScoreResult? {
        BodyScoreCache.shared.latestResult(for: authManager.currentUser?.id)
    }

    private func dynamicBodyScoreResult() -> BodyScoreResult? {
        guard let metric = currentMetric,
              let profile = authManager.currentUser?.profile else {
            return nil
        }

        let genderString = profile.gender?.lowercased() ?? ""
        let sex: BiologicalSex
        if genderString.contains("female") || genderString.contains("woman") {
            sex = .female
        } else if genderString.contains("male") || genderString.contains("man") {
            sex = .male
        } else {
            return nil
        }

        let calendar = Calendar.current
        let birthYear: Int?
        if let dateOfBirth = profile.dateOfBirth {
            birthYear = calendar.component(.year, from: dateOfBirth)
        } else {
            birthYear = nil
        }

        guard let resolvedBirthYear = birthYear else {
            return nil
        }

        guard let heightCm = profile.height, heightCm > 0 else { return nil }
        let heightValue = HeightValue(value: heightCm, unit: .centimeters)

        let bodyFat: Double
        if let direct = metric.bodyFatPercentage {
            bodyFat = direct
        } else if let estimated = MetricsInterpolationService.shared.estimateBodyFat(
            for: metric.date,
            metrics: bodyMetrics
        )?.value {
            bodyFat = estimated
        } else {
            return nil
        }

        let trendWeightResult = MetricsInterpolationService.shared.estimateTrendWeight(
            for: metric.date,
            metrics: bodyMetrics
        )

        let weightKg: Double
        if let trend = trendWeightResult?.value {
            weightKg = trend
        } else if let raw = metric.weight {
            weightKg = raw
        } else {
            return nil
        }

        let weightValue = WeightValue(value: weightKg, unit: .kilograms)
        let bodyFatValue = BodyFatValue(percentage: bodyFat, source: .manualValue)
        let healthSnapshot = HealthImportSnapshot(
            heightCm: heightCm,
            weightKg: weightKg,
            bodyFatPercentage: bodyFat,
            birthYear: resolvedBirthYear
        )

        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        let input = BodyScoreInput(
            sex: sex,
            birthYear: resolvedBirthYear,
            height: heightValue,
            weight: weightValue,
            bodyFat: bodyFatValue,
            measurementPreference: system,
            healthSnapshot: healthSnapshot
        )

        guard input.isReadyForCalculation else { return nil }

        let context = BodyScoreCalculationContext(input: input, calculationDate: metric.date)
        let calculator = BodyScoreCalculator()

        guard let result = try? calculator.calculateScore(context: context) else {
            return nil
        }

        return result
    }

    func heroBodyScoreDeltaText() -> String? {
        guard latestBodyScoreResult() != nil else {
            return nil
        }
        return "+0.0 last 30d"
    }

    // MARK: - Primary Metric Card

    var stepsCard: some View {
        let stepsValue = dailyMetrics?.steps ?? 0
        let goalValue = max(stepGoal, 1)
        let formattedSteps = formatSteps(stepsValue)
        let formattedGoal = formatSteps(goalValue)
        let subtext = stepsGoalSubtext(steps: stepsValue, goal: goalValue)

        return DashboardStepsCard(
            formattedSteps: formattedSteps,
            formattedGoal: formattedGoal,
            subtext: subtext,
            progressView: {
                stepsProgressBar(steps: stepsValue, goal: goalValue)
            },
            onTap: {
                selectedMetricType = .steps
                isMetricDetailActive = true
            }
        )
    }

    // MARK: - Progress Bars

    func stepsProgressBar(steps: Int, goal: Int) -> some View {
        let clampedGoal = max(goal, 1)
        let progress = max(0, min(Double(steps) / Double(clampedGoal), 1))

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white.opacity(0.15))

                RoundedRectangle(cornerRadius: 999)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#6EE7F0"),
                                Color(hex: "#22C1C3")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }
    }

    func bodyFatProgressBar(current: Double, goal: Double) -> some View {
        // Body fat range: 0% to 40% (human range)
        let minBF: Double = 0
        let maxBF: Double = 40
        let range = maxBF - minBF

        // Calculate positions (0.0 to 1.0)
        let currentPosition = max(0, min(1, (current - minBF) / range))
        let goalPosition = max(0, min(1, (goal - minBF) / range))

        return VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                // Progress fill (from min to current value)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#6EE7F0"))
                    .frame(width: max(0, currentPosition * 60), height: 4)

                // Goal indicator tick
                Rectangle()
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 2, height: 8)
                    .offset(x: goalPosition * 60 - 1)
            }
            .frame(width: 60, height: 8)
        }
    }

    func weightProgressBar(current: Double, goal: Double?, unit: String) -> some View {
        if let goal = goal {
            // Determine reasonable weight range based on goal
            let range = goal * 0.4  // 40% range (±20% from goal)
            let minWeight = goal - (range / 2)
            let maxWeight = goal + (range / 2)

            // Calculate positions (0.0 to 1.0)
            let currentPosition = max(0, min(1, (current - minWeight) / (maxWeight - minWeight)))
            let goalPosition: Double = 0.5  // Goal is always in the middle

            return AnyView(
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 4)

                        // Progress fill (from min to current value)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#6EE7F0"))
                            .frame(width: max(0, currentPosition * 60), height: 4)

                        // Goal indicator tick
                        Rectangle()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: 2, height: 8)
                            .offset(x: goalPosition * 60 - 1)
                    }
                    .frame(width: 60, height: 8)
                }
            )
        } else {
            // No goal set - show "Tap to set" placeholder
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.40))

                    Text("Tap to set")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.40))
                }
                .frame(width: 60, height: 8)
            )
        }
    }

    func stepsGoalSubtext(steps: Int, goal: Int) -> String {
        let remaining = max(goal - steps, 0)
        guard remaining > 0 else {
            return "Goal reached"
        }

        let formattedRemaining = FormatterCache.stepsFormatter.string(from: NSNumber(value: remaining)) ?? "\(remaining)"
        return "\(formattedRemaining) to goal"
    }

    // MARK: - Quick Actions

    var quickActions: some View {
        HStack(spacing: 12) {
            GlassPillButton(icon: "plus.circle.fill", title: "Log Weight") {
                showAddEntrySheet = true
            }

            GlassPillButton(icon: "square.and.arrow.up.fill", title: "Share Score") {
                if let payload = makeBodyScoreSharePayload() {
                    bodyScoreSharePayload = payload
                    isBodyScoreSharePresented = true
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func makeBodyScoreSharePayload() -> BodyScoreSharePayload? {
        let bodyScore = bodyScoreText()

        // Avoid prompting to share when the score is effectively missing
        guard bodyScore.score > 0 else {
            return nil
        }

        let ffmiValue = heroFFMIValue()
        let ffmiCaption = heroFFMICaption()
        let bodyFatValue = heroBodyFatValue()
        let bodyFatCaption = heroBodyFatCaption()
        let weightValue = heroWeightValue()
        let weightCaption = heroWeightCaption()
        let deltaText = heroBodyScoreDeltaText()

        return BodyScoreSharePayload(
            score: bodyScore.score,
            scoreText: bodyScore.scoreText,
            tagline: bodyScore.tagline,
            ffmiValue: ffmiValue,
            ffmiCaption: ffmiCaption,
            bodyFatValue: bodyFatValue,
            bodyFatCaption: bodyFatCaption,
            weightValue: weightValue,
            weightCaption: weightCaption,
            deltaText: deltaText
        )
    }

    // MARK: - Visual Divider

    var visualDivider: some View {
        Rectangle()
            .fill(Color.liquidTextPrimary.opacity(0.15))
            .frame(height: 1)
    }
}
