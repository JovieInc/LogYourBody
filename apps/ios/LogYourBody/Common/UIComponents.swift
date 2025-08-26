//
// UIComponents.swift
// LogYourBody
//
import SwiftUI

enum Trend {
    case up(Double)
    case down(Double)
    case neutral
}

// MARK: - Metric Card Component
struct MetricCard: View {
    let value: String
    let label: String
    let icon: String
    let trend: Trend
    let isEstimated: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if isEstimated {
                    Text("EST")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                
                switch trend {
                case .up(let change):
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                        Text(String(format: "%.1f", change))
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                case .down(let change):
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                        Text(String(format: "%.1f", change))
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                case .neutral:
                    EmptyView()
                }
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

// MARK: - Glass Card Component
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16
    
    init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                Group {
                    if #available(iOS 18.0, *) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(Color.white.opacity(0.05))
                            )
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.appCard)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
    }
}

// MARK: - Header Bar Component
struct HeaderBar<Leading: View, Trailing: View>: View {
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
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

// MARK: - Metric Gauge Component
struct MetricGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String
    let color: Color
    var size = CGSize(width: 140, height: 140)
    
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
            // Background circle
            Circle()
                .stroke(Color.appBorder, lineWidth: 2)
                .frame(width: size.width, height: size.height)
            
            // Progress arc
            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .frame(width: size.width - 16, height: size.height - 16)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: normalizedValue)
            
            // Content
            VStack(spacing: 4) {
                Text(displayValue)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.appText)
                
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.appTextSecondary)
                
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.appTextTertiary)
            }
        }
    }
}

// MARK: - Bottom Navigation Glass Component
struct BottomNavGlass: View {
    let selectedTab: String
    let onTabSelected: (String) -> Void
    
    private let tabs = [
        ("house.fill", "Home"),
        ("calendar", "Timeline"),
        ("camera.fill", "Photos"),
        ("person.fill", "Profile")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.1) { icon, title in
                let isSelected = selectedTab == title
                Button(
                    action: {
                        HapticManager.shared.buttonTapped()
                        onTabSelected(title)
                    },
                    label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 22))
                                .foregroundColor(isSelected ? .appPrimary : .appTextSecondary)
                            
                            Text(title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .appPrimary : .appTextSecondary)
                        }
                    .frame(maxWidth: .infinity)
                }
        )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Group {
                if #available(iOS 18.0, *) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Rectangle()
                                .fill(Color.appBackground.opacity(0.85))
                        )
                } else {
                    Rectangle()
                        .fill(Color.appBackground.opacity(0.95))
                        .background(.regularMaterial)
                }
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

// MARK: - Circular Progress Component
struct CircularProgress: View {
    let progress: Double
    let lineWidth: CGFloat = 4
    let size: CGFloat = 100
    let color: Color = .appPrimary
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appBorder, lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        }
    }
}

// MARK: - Empty State View
struct UIEmptyStateView: View {
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

// MARK: - Loading Overlay
struct UILoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.appCard)
            )
        }
    }
}

// MARK: - Metric Card Component
struct UIMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let trend: Double? // Positive for up, negative for down
    let icon: String
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.appPrimary)
                    
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                    
                    Spacer()
                    
                    if let trend = trend {
                        HStack(spacing: 4) {
                            Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(abs(Int(trend)))%")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(trend > 0 ? .green : .red)
                    }
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.appText)
                    
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct UIComponents_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Glass Card
                GlassCard {
                    Text("Glass Card Content")
                        .foregroundColor(.appText)
                }
                .padding()
                
                // Header Bar
                HeaderBar(title: "Dashboard") {
                    Button(
            action: {},
            label: {
                        Image(systemName: "gear")
                            .foregroundColor(.appText)
                    }
        )
                } trailing: {
                    Button(
            action: {},
            label: {
                        Image(systemName: "plus")
                            .foregroundColor(.appText)
                    }
        )
                }
                
                // Metric Gauge
                MetricGauge(
                    value: 15.5,
                    maxValue: 30,
                    label: "Body Fat",
                    unit: "%BF",
                    color: .green
                )
                
                // Metric Card
                MetricCard(
                    value: "180.5",
                    label: "Weight (lbs)",
                    icon: "scalemass",
                    trend: .down(2.5),
                    isEstimated: false
                )
                .padding()
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
