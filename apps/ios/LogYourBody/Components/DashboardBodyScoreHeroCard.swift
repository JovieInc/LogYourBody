import SwiftUI

struct BodyScoreGaugeView: View {
    let score: Int

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let radius = width * 0.45
            let lineWidth: CGFloat = 10
            let progress = max(0, min(Double(score) / 100.0, 1.0))

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(
                        Color.white.opacity(0.15),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .trim(from: 0, to: 0.5 * progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.metricAccent,
                                Color.metricAccent.opacity(0.6),
                                Color.metricAccent
                            ]),
                            center: .center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth + 2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [10, 10]
                        )
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .shadow(
                        color: Color.metricAccent.opacity(0.4),
                        radius: 8,
                        x: 0,
                        y: 0
                    )
                    .animation(
                        .spring(response: 0.8, dampingFraction: 0.8),
                        value: score
                    )
            }
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 120)
    }
}

struct DashboardBodyScoreHeroCard: View {
    let score: Int
    let scoreText: String
    let tagline: String
    let ffmiValue: String
    let ffmiCaption: String
    let bodyFatValue: String
    let bodyFatCaption: String
    let weightValue: String
    let weightCaption: String
    let deltaText: String?
    let onTapBodyScore: (() -> Void)?
    let onTapFFMI: (() -> Void)?
    let onTapBodyFat: (() -> Void)?
    let onTapWeight: (() -> Void)?

    var body: some View {
        HeroGlassCard {
            VStack(alignment: .leading, spacing: 20) {
                header

                gaugeAndSummary

                HStack(spacing: 18) {
                    tappableHeroStatTile(
                        title: "FFMI",
                        value: ffmiValue,
                        caption: ffmiCaption,
                        onTap: onTapFFMI
                    )
                    tappableHeroStatTile(
                        title: "Body Fat",
                        value: bodyFatValue,
                        caption: bodyFatCaption,
                        onTap: onTapBodyFat
                    )
                    tappableHeroStatTile(
                        title: "Weight",
                        value: weightValue,
                        caption: weightCaption,
                        onTap: onTapWeight
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Body Score")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))

            Spacer()

            if let deltaText {
                GlassChip(
                    icon: deltaIcon(for: deltaText),
                    text: deltaText,
                    color: deltaColor(for: deltaText)
                )
            }
        }
    }

    private var gaugeAndSummary: some View {
        VStack(spacing: 16) {
            BodyScoreGaugeView(score: score)

            VStack(spacing: 6) {
                Text(scoreText)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Text(tagline)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(projectionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTapBodyScore?()
        }
    }

    private var projectionText: String {
        guard let deltaText,
              let deltaValue = parsedDelta(from: deltaText) else {
            return "Stable over 30 days."
        }

        let absoluteDelta = abs(deltaValue)

        // Treat very small changes as effectively flat
        if absoluteDelta < 0.5 {
            return "Stable over 30 days."
        }

        let projectedScore = max(0, min(100, Double(score) + deltaValue))
        let projectedScoreText = String(format: "%.0f", projectedScore)
        let formattedDelta = formatDelta(deltaValue)

        return "On pace for \(projectedScoreText) (\(formattedDelta)) in 30d"
    }

    private func parsedDelta(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let firstToken = trimmed.split(separator: " ").first else {
            return nil
        }

        var numericString = String(firstToken)
        numericString = numericString.replacingOccurrences(of: "+", with: "")
        numericString = numericString.replacingOccurrences(of: "\u{2013}", with: "-")

        return Double(numericString)
    }

    private func formatDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "\u{2013}"
        let magnitude = abs(value)
        let rounded = (magnitude * 10).rounded() / 10

        if rounded == rounded.rounded() {
            return "\(sign)\(Int(rounded))"
        }

        return String(format: "%@%.1f", sign, rounded)
    }

    private func tappableHeroStatTile(
        title: String,
        value: String,
        caption: String,
        onTap: (() -> Void)?
    ) -> some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    heroStatTile(title: title, value: value, caption: caption)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                heroStatTile(title: title, value: value, caption: caption)
            }
        }
    }

    private func heroStatTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.6))

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color.liquidTextPrimary)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaIcon(for deltaText: String) -> String {
        let trimmed = deltaText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("–") || trimmed.hasPrefix("-") {
            return "arrow.down.right"
        }
        return "arrow.up.right"
    }

    private func deltaColor(for deltaText: String) -> Color {
        let trimmed = deltaText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("–") || trimmed.hasPrefix("-") {
            return Color.metricDeltaNegative
        }
        return Color.metricDeltaPositive
    }
}
