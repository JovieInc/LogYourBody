//
// StateViews.swift
// LogYourBody
//
import SwiftUI

// MARK: - Loading View

struct DesignLoadingView: View {
    let message: String?
    let progress: Double?
    let style: LoadingStyle

    enum LoadingStyle {
        case standard
        case overlay
        case minimal
        case fullScreen
    }

    init(
        message: String? = nil,
        progress: Double? = nil,
        style: LoadingStyle = .standard
    ) {
        self.message = message
        self.progress = progress
        self.style = style
    }

    var body: some View {
        switch style {
        case .standard:
            standardLoading
        case .overlay:
            overlayLoading
        case .minimal:
            minimalLoading
        case .fullScreen:
            fullScreenLoading
        }
    }

    private var standardLoading: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .appPrimary))
                .scaleEffect(1.5)

            if let message = message {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let progress = progress {
                VStack(spacing: 4) {
                    ProgressBar(progress: progress)
                        .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }
        }
        .padding(24)
    }

    private var overlayLoading: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { } // Prevent tap through

            // Loading content
            StandardCard(style: .elevated) {
                standardLoading
            }
            .frame(maxWidth: 280)
        }
    }

    private var minimalLoading: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                .scaleEffect(0.8)

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private var fullScreenLoading: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                VStack(spacing: 32) {
                    // Animated logo or icon
                    Image(systemName: "heart.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.appPrimary)
                        .scaleEffect(animatingScale)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true)
                            ) {
                                animatingScale = 1.2
                            }
                        }

                    VStack(spacing: 12) {
                        if let message = message {
                            Text(message)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        if let progress = progress {
                            VStack(spacing: 8) {
                                ProgressBar(progress: progress)
                                    .frame(width: min(300, geometry.size.width * 0.8))

                                Text("\(Int(progress * 100))%")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .appPrimary))
                                .scaleEffect(1.2)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
        }
    }

    @State private var animatingScale: CGFloat = 1.0
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(Color.secondary.opacity(0.6))
                .padding(.bottom, 8)

            // Text content
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action button
            if let actionTitle = actionTitle, let action = action {
                BaseButton(
                    actionTitle,
                    configuration: ButtonConfiguration(style: .primary),
                    action: action
                )
                .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
                .padding(.bottom, 8)

            // Error message
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Retry button
            if let retryAction = retryAction {
                BaseButton(
                    "Try Again",
                    configuration: ButtonConfiguration(
                        style: .primary,
                        icon: "arrow.clockwise"
                    ),
                    action: retryAction
                )
                .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
    }
}

// MARK: - Success View

struct SuccessView: View {
    let title: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @State private var showCheckmark = false
    @State private var animateCheckmark = false

    var body: some View {
        VStack(spacing: 16) {
            // Success checkmark
            ZStack {
                Circle()
                    .fill(.green.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
                    .opacity(showCheckmark ? 1 : 0)
                    .rotationEffect(.degrees(animateCheckmark ? 0 : -30))
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showCheckmark = true
                    animateCheckmark = true
                }
            }

            // Text content
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if let description = description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Action button
            if let actionTitle = actionTitle, let action = action {
                BaseButton(
                    actionTitle,
                    configuration: ButtonConfiguration(style: .primary),
                    action: action
                )
                .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    let showPercentage: Bool

    init(progress: Double, showPercentage: Bool = false) {
        self.progress = min(max(progress, 0), 1)
        self.showPercentage = showPercentage
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.appCard.opacity(0.5))
                    .frame(height: 6)

                // Progress
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.appPrimary)
                    .frame(width: geometry.size.width * progress, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Percentage label
                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                        .background(
                            Capsule()
                                .fill(Color.appCard)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.appBorder, lineWidth: 1)
                                )
                        )
                        .offset(x: (geometry.size.width * progress) - 25)
                        .offset(y: -20)
                }
            }
        }
        .frame(height: showPercentage ? 30 : 6)
    }
}

// MARK: - Skeleton Loading

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var isAnimating = false

    init(
        width: CGFloat? = nil,
        height: CGFloat = 20,
        cornerRadius: CGFloat = 4
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.appCard.opacity(0.5))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                        .animation(
                            .linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
                .clipped()
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

struct StateViews_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            ScrollView {
                VStack(spacing: 40) {
                    // Loading views
                    DesignLoadingView(message: "Loading your data...")

                    DesignLoadingView(
                        message: "Uploading photo...",
                        progress: 0.65
                    )

                    DesignLoadingView(
                        message: "Syncing",
                        style: .minimal
                    )

                    // Empty state
                    EmptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "No Photos Yet",
                        description: "Take your first progress photo to start tracking your transformation",
                        actionTitle: "Take Photo"
                    ) { }

                    // Error view
                    ErrorView(
                        error: NSError(
                            domain: "",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to connect to server"]
                        )
                    ) { }

                    // Success view
                    SuccessView(
                        title: "Profile Updated!",
                        description: "Your changes have been saved successfully",
                        actionTitle: "Continue"
                    ) { }

                    // Progress bar
                    ProgressBar(progress: 0.7, showPercentage: true)
                        .frame(width: 200)

                    // Skeleton loading
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonView(width: 150, height: 24)
                        SkeletonView(height: 16)
                        SkeletonView(height: 16)
                        SkeletonView(width: 100, height: 16)
                    }
                    .padding()
                }
                .padding()
            }
            .background(Color.black)
        }
    }
}
