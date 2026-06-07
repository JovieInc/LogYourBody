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
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.appBackground, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    featuresSection

                    if let package = firstAvailablePackage {
                        pricingCard(package: package)
                    } else if isLoading {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        plansUnavailableState
                    }

                    if let package = firstAvailablePackage {
                        purchaseButton(package: package)
                    }

                    restorePurchasesButton
                    logoutButton
                    legalLinks

                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
            .accessibilityIdentifier("paywall_screen")

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
        .confirmationDialog(
            "Log out of LogYourBody?",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                Task {
                    AnalyticsService.shared.track(event: "paywall_logout")
                    await authManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this to switch accounts on this device.")
        }
        .onAppear {
            // Use cached offerings if available, otherwise fetch
            if revenueCatManager.currentOffering != nil {
                isLoading = false
                // print("💰 Using cached offerings")
            } else {
                Task {
                    await loadOfferings()
                }
            }

            AnalyticsService.shared.track(event: "paywall_view")
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationView {
                LegalDocumentView(documentType: .terms)
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationView {
                LegalDocumentView(documentType: .privacy)
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
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.appPrimary)

            Text("LogYourBody Pro")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.appText)
                .accessibilityIdentifier("paywall_title")

            Text("Log your body in under 10 seconds and see if you are moving in the right direction.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallFeatureRow(
                icon: "scalemass.fill",
                title: "Daily logging",
                description: "Save weight and body fat fast."
            )

            PaywallFeatureRow(
                icon: "chart.xyaxis.line",
                title: "Clear trends",
                description: "See weight, body fat, FFMI, and body score."
            )

            PaywallFeatureRow(
                icon: "icloud.fill",
                title: "Private sync",
                description: "Keep local data backed up to your account."
            )
        }
        .padding(.horizontal, 8)
    }

    private func pricingCard(package: Package) -> some View {
        VStack(spacing: 14) {
            if let trialText = revenueCatManager.getTrialDurationText(package: package) {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14, weight: .semibold))

                    Text(trialText.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.appPrimary)
                .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(revenueCatManager.formatPrice(package: package))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.appText)

                    Text(billingPeriodSuffix(for: package))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }

                Text(packageSummaryText(for: package))
                    .font(.system(size: 15))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appCard.opacity(0.95))

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.appBorder.opacity(0.8), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 12)
    }

    private func purchaseButton(package: Package) -> some View {
        Button {
            Task {
                AnalyticsService.shared.track(
                    event: "purchase_start",
                    properties: [
                        "package_id": package.identifier
                    ]
                )

                let success = await revenueCatManager.purchase(package: package)
                if !success && revenueCatManager.errorMessage != nil {
                    showPurchaseError = true
                }

                AnalyticsService.shared.track(
                    event: success ? "purchase_success" : "purchase_failed",
                    properties: [
                        "package_id": package.identifier
                    ]
                )
            }
        } label: {
            HStack(spacing: 12) {
                if !revenueCatManager.isPurchasing {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }

                Text(revenueCatManager.isPurchasing ? "Processing..." : purchaseButtonTitle(for: package))
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appPrimary)
            .cornerRadius(16)
        }
        .disabled(revenueCatManager.isPurchasing)
        .accessibilityIdentifier("paywall_purchase_button")
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

                AnalyticsService.shared.track(
                    event: success ? "restore_success" : "restore_failed"
                )
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .disabled(revenueCatManager.isPurchasing)
        .accessibilityIdentifier("paywall_restore_purchases_button")
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.notification(type: .warning)
            showLogoutConfirmation = true
        } label: {
            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.red.opacity(0.85))
        }
        .disabled(revenueCatManager.isPurchasing)
        .accessibilityLabel("Log out")
        .accessibilityHint("Signs you out so you can use another account.")
        .accessibilityIdentifier("paywall_logout_button")
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button {
                showTermsSheet = true
            } label: {
                Text("Terms of Service")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Text("•")
                .foregroundColor(.white.opacity(0.3))

            Button {
                showPrivacySheet = true
            } label: {
                Text("Privacy Policy")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var plansUnavailableState: some View {
        VStack(spacing: 12) {
            Text("Subscription plans are unavailable")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.appText)

            Text("Check your connection and retry.")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)

            Button {
                Task {
                    await loadOfferings()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.appCard)
                    .cornerRadius(12)
            }
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.appCard.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder.opacity(0.8), lineWidth: 1)
        )
        .cornerRadius(16)
        .accessibilityIdentifier("paywall_plans_unavailable_state")
    }

    private func billingPeriodSuffix(for package: Package) -> String {
        let period = billingPeriodLabel(for: package)
        return period.isEmpty ? "" : "/\(period)"
    }

    private func packageSummaryText(for package: Package) -> String {
        let period = billingPeriodLabel(for: package)
        if period.isEmpty {
            return "Billed by the App Store."
        }

        return "Billed \(period)ly by the App Store."
    }

    private func purchaseButtonTitle(for package: Package) -> String {
        revenueCatManager.getTrialDurationText(package: package) == nil ? "Subscribe" : "Start trial"
    }

    private func billingPeriodLabel(for package: Package) -> String {
        let identifier = "\(package.identifier) \(package.storeProduct.productIdentifier)".lowercased()

        if identifier.contains("annual") || identifier.contains("year") {
            return "year"
        }

        if identifier.contains("month") {
            return "month"
        }

        if identifier.contains("week") {
            return "week"
        }

        return ""
    }

    // MARK: - Functions

    private func loadOfferings() async {
        isLoading = true
        await revenueCatManager.fetchOfferings()
        isLoading = false

        if revenueCatManager.currentOffering == nil {
            // print("⚠️ No offerings available")
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
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 30, height: 28, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.appText)

                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.appTextSecondary)
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
