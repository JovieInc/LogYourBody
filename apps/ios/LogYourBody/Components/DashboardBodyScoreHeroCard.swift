import SwiftUI

struct DashboardBodyScoreHeroCard: View {
    let score: Int
    let scoreText: String
    let tagline: String
    let ffmiValue: String
    let ffmiCaption: String
    let percentileValue: String
    let targetRange: String
    let targetCaption: String

    var body: some View {
        HeroGlassCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Body Score")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))

                        Text(scoreText)
                            .font(.system(size: 78, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Text(tagline)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                    }

                    Spacer()

                    progressRing(for: score)
                        .frame(width: 120, height: 120)
                }

                HStack(spacing: 18) {
                    heroStatTile(title: "FFMI", value: ffmiValue, caption: ffmiCaption)
                    heroStatTile(title: "Lean %ile", value: percentileValue, caption: "Among peers")
                    heroStatTile(title: "Target", value: targetRange, caption: targetCaption)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func progressRing(for score: Int) -> some View {
        let progress = Double(score) / 100.0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "#6EE7F0"), Color(hex: "#3A7BD5")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 12
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)

            VStack(spacing: 4) {
                Text("Score")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                Text("/100")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.45))
            }
        }
        .frame(width: 90, height: 90)
    }
}
