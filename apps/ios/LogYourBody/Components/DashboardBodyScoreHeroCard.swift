import SwiftUI

struct BodyScoreGaugeView: View {
    let score: Int
    let scoreText: String

    var body: some View {
        let progress = max(0, min(Double(score) / 100.0, 1.0))

        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.14),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.metricAccent,
                            Color.metricAccent.opacity(0.58),
                            Color.metricAccent
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.metricAccent.opacity(0.35), radius: 8, x: 0, y: 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: score)

            VStack(spacing: 0) {
                Text(scoreText)
                    .font(.system(size: 42, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)

                Text("/100")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.45))
            }
        }
        .frame(width: 118, height: 118)
        .accessibilityLabel("Body Score \(scoreText)")
    }
}

struct DashboardBodyScoreHeroCard: View {
    let score: Int
    let scoreText: String
    let tagline: String
    let ffmiValue: String
    let bodyFatValue: String
    let weightValue: String
    let deltaText: String?
    let onTapBodyScore: (() -> Void)?
    let onTapFFMI: (() -> Void)?
    let onTapBodyFat: (() -> Void)?
    let onTapWeight: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
                gaugeAndSummary

                HStack(spacing: 12) {
                    tappableHeroStatTile(
                        title: "FFMI",
                        value: ffmiValue,
                        onTap: onTapFFMI
                    )
                    tappableHeroStatTile(
                        title: "Body Fat",
                        value: bodyFatValue,
                        onTap: onTapBodyFat
                    )
                    tappableHeroStatTile(
                        title: "Weight",
                        value: weightValue,
                        onTap: onTapWeight
                    )
                }
                .accessibilityIdentifier("dashboard_body_score_hero_stats")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovieSurface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                .stroke(Color.jovieHairline.opacity(JovieTokens.hairlineOpacity), lineWidth: 1)
        }
        .accessibilityIdentifier("dashboard_body_score_hero")
    }

    private var gaugeAndSummary: some View {
        HStack(alignment: .center, spacing: 20) {
            BodyScoreGaugeView(score: score, scoreText: scoreText)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapBodyScore?()
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("Body Score")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.62))

                Text(tagline)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let deltaText {
                    HStack(spacing: 8) {
                        Image(systemName: deltaIcon(for: deltaText))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(deltaColor(for: deltaText).opacity(0.8))
                        Text(deltaText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(deltaColor(for: deltaText).opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .dashboardChromeGlass(
                        in: Capsule(style: .continuous),
                        cornerRadius: 999,
                        tint: deltaColor(for: deltaText)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tappableHeroStatTile(
        title: String,
        value: String,
        onTap: (() -> Void)?
    ) -> some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    heroStatTile(title: title, value: value)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                heroStatTile(title: title, value: value)
            }
        }
    }

    private func heroStatTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DSMetricLabel(
                text: title.uppercased(),
                size: .system(size: 12),
                weight: .semibold,
                color: Color.liquidTextPrimary.opacity(0.6)
            )
            .lineLimit(1)

            DSMetricValue(
                value: value,
                unit: nil,
                size: .system(size: 19, weight: .bold, design: .default),
                color: Color.liquidTextPrimary
            )
            .lineLimit(1)
            .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
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
