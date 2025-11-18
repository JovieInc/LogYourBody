//
// DashboardComponents.swift
// LogYourBody
//
import SwiftUI

// MARK: - Empty State View

struct DashboardEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String = "Get Started"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.appTextSecondary)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.appText)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.appPrimary)
                        .cornerRadius(24)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

// MARK: - Metric Gauge

struct DashboardMetricGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String
    let color: Color
    var size = CGSize(width: 100, height: 100)

    private var normalizedValue: Double {
        min(1.0, max(0.0, value / maxValue))
    }

    private var displayValue: String {
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }

    var body: some View {
        ZStack {
            // Background circle - 1pt gray remainder
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: size.width, height: size.height)

            // Progress arc - 3pt white ring (monochrome)
            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: normalizedValue)

            // Content
            VStack(spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Header Bar

struct DashboardHeaderBar<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing
    var showLiquidGlass: Bool = true

    init(
        title: String = "",
        showLiquidGlass: Bool = true,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.showLiquidGlass = showLiquidGlass
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            leading

            Spacer()

            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.appText)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if showLiquidGlass {
                    if #available(iOS 18.0, *) {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Rectangle()
                                    .fill(Color.appBackground.opacity(0.8))
                            )
                    } else {
                        Rectangle()
                            .fill(Color.appBackground.opacity(0.95))
                    }
                }
            }
        )
        .overlay(
            Group {
                if showLiquidGlass {
                    Rectangle()
                        .fill(Color.appBorder)
                        .frame(height: 0.5)
                }
            },
            alignment: .bottom
        )
    }
}
