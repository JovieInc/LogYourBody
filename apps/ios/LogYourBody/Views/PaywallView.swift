//
// PaywallView.swift
// LogYourBody
//
// Premium subscription paywall with glassmorphic design
//
import SwiftUI
import RevenueCat

struct PaywallView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @State private var isLoading = true
    @State private var showRestoreSuccess = false
    @State private var showRestoreError = false
    @State private var showPurchaseError = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.black, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    header

                    // Features List
                    featuresSection

                    // Pricing Card
                    if let package = firstAvailablePackage {
                        pricingCard(package: package)
                    } else if isLoading {
                        ProgressView()
                            .tint(Color(hex: "#6EE7F0"))
                    } else {
                        // No packages available - show error
                        Text("No subscription plans available")
                            .foregroundColor(.white.opacity(0.7))
                            .padding()

                        Text("Please check your internet connection and try again")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Purchase Button
                    if let package = firstAvailablePackage {
                        purchaseButton(package: package)
                    }

                    // Restore purchases
                    restorePurchasesButton

                    // Legal links
                    legalLinks

                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }

            // Loading overlay
            if revenueCatManager.isPurchasing {
                LoadingOverlay(message: "Processing purchase...")
            }
        }
        .alert("Purchase Error", isPresented: $showPurchaseError) {
            Button("OK", role: .cancel) {
                revenueCatManager.errorMessage = nil
            }
        } message: {
            Text(revenueCatManager.errorMessage ?? "An error occurred")
        }
        .alert("Restore Successful", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your subscription has been restored!")
        }
        .alert("No Subscription Found", isPresented: $showRestoreError) {
            Button("OK", role: .cancel) {
                revenueCatManager.errorMessage = nil
            }
        } message: {
            Text(revenueCatManager.errorMessage ?? "No active subscription found")
        }
        .onAppear {
            // Use cached offerings if available, otherwise fetch
            if revenueCatManager.currentOffering != nil {
                isLoading = false
                print("💰 Using cached offerings")
            } else {
                Task {
                    await loadOfferings()
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Returns the first available package, preferring annual but falling back to any available package
    private var firstAvailablePackage: Package? {
        // Try annual first (preferred)
        if let annual = revenueCatManager.currentOffering?.package(identifier: "$rc_annual") {
            return annual
        }
        // Fallback to monthly
        if let monthly = revenueCatManager.currentOffering?.package(identifier: "$rc_monthly") {
            return monthly
        }
        // Fallback to first available package of any type
        return revenueCatManager.currentOffering?.availablePackages.first
    }

    // MARK: - Components

    private var header: some View {
        VStack(spacing: 16) {
            // App icon/logo
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#6EE7F0"), Color(hex: "#4FA9B1")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: "#6EE7F0").opacity(0.3), radius: 20, x: 0, y: 10)

            Text("LogYourBody Pro")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("Track your transformation")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaywallFeatureRow(
                icon: "camera.fill",
                title: "Progress Photos",
                description: "Visual timeline of your transformation"
            )

            PaywallFeatureRow(
                icon: "chart.xyaxis.line",
                title: "Advanced Analytics",
                description: "Track weight, body fat, and FFMI trends"
            )

            PaywallFeatureRow(
                icon: "heart.fill",
                title: "HealthKit Sync",
                description: "Seamless integration with Apple Health"
            )

            PaywallFeatureRow(
                icon: "icloud.fill",
                title: "Cloud Backup",
                description: "Your data safely synced across devices"
            )

            PaywallFeatureRow(
                icon: "sparkles",
                title: "Premium Features",
                description: "Unlock all current and future features"
            )
        }
        .padding(.horizontal, 8)
    }

    private func pricingCard(package: Package) -> some View {
        VStack(spacing: 16) {
            // Trial badge
            if let trialText = revenueCatManager.getTrialDurationText(package: package) {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14, weight: .semibold))

                    Text(trialText.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#6EE7F0"), Color(hex: "#4FA9B1")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: Color(hex: "#6EE7F0").opacity(0.4), radius: 15, x: 0, y: 5)
            }

            // Price
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(revenueCatManager.formatPrice(package: package))
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)

                    Text("/year")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Text("Just $5.75 per month, billed annually")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            ZStack {
                // Glass background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                // Border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                // Accent glow
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#6EE7F0").opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    private func purchaseButton(package: Package) -> some View {
        Button {
            Task {
                let success = await revenueCatManager.purchase(package: package)
                if !success && revenueCatManager.errorMessage != nil {
                    showPurchaseError = true
                }
            }
        } label: {
            HStack(spacing: 12) {
                if !revenueCatManager.isPurchasing {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }

                Text(revenueCatManager.isPurchasing ? "Processing..." : "Start Free Trial")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#6EE7F0"), Color(hex: "#4FA9B1")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color(hex: "#6EE7F0").opacity(0.4), radius: 20, x: 0, y: 10)
        }
        .disabled(revenueCatManager.isPurchasing)
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                let success = await revenueCatManager.restorePurchases()
                if success {
                    showRestoreSuccess = true
                } else if revenueCatManager.errorMessage != nil {
                    showRestoreError = true
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .disabled(revenueCatManager.isPurchasing)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Link("Terms of Service", destination: URL(string: "https://www.logyourbody.com/terms")!)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Text("•")
                .foregroundColor(.white.opacity(0.3))

            Link("Privacy Policy", destination: URL(string: "https://www.logyourbody.com/privacy")!)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Functions

    private func loadOfferings() async {
        isLoading = true
        await revenueCatManager.fetchOfferings()
        isLoading = false

        if revenueCatManager.currentOffering == nil {
            print("⚠️ No offerings available")
        }
    }
}

// MARK: - Feature Row Component

private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "#6EE7F0").opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "#6EE7F0"))
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(AuthManager())
        .environmentObject(RevenueCatManager.shared)
}
