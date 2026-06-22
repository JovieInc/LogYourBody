//
// PaywallView.swift
// LogYourBody
//
// Premium subscription paywall with glassmorphic design
//
import SwiftUI

struct PaywallView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var isLoading = true
    @State private var showRestoreSuccess = false
    @State private var showRestoreError = false
    @State private var showPurchaseError = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showLogoutConfirmation = false
    @State private var selectedPackageIdentifier = "$rc_annual"

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

                    if !availablePrimaryPackages.isEmpty {
                        pricingOptionsSection(packages: availablePrimaryPackages)
                    } else if isLoading {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        plansUnavailableState(
                            cachedPackage: subscriptionManager.cachedPaywallOfferingDisplay?.preferredPackage
                        )
                    }

                    if let package = selectedPackage {
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
            if subscriptionManager.isPurchasing {
                LoadingOverlay(message: "Processing purchase...")
            }
        }
        .alert("Purchase Error", isPresented: $showPurchaseError) {
            Button("OK", role: .cancel) {
                subscriptionManager.errorMessage = nil
            }
        } message: {
            Text(subscriptionManager.errorMessage ?? "An error occurred")
        }
        .alert("Restore Successful", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your subscription has been restored!")
        }
        .alert("No Subscription Found", isPresented: $showRestoreError) {
            Button("OK", role: .cancel) {
                subscriptionManager.errorMessage = nil
            }
        } message: {
            Text(subscriptionManager.errorMessage ?? "No active subscription found")
        }
        .confirmationDialog(
            "Log out of LogYourBody?",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                Task {
                    AppServicePorts.analyticsTracker.track(event: "paywall_logout")
                    await authManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this to switch accounts on this device.")
        }
        .onAppear {
            // Use cached offerings if available, otherwise fetch
            if !subscriptionManager.paywallPackages.isEmpty {
                isLoading = false
                // print("💰 Using cached offerings")
            } else {
                Task {
                    await loadOfferings()
                }
            }

            AppServicePorts.analyticsTracker.track(event: "paywall_view")
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationStack {
                LegalDocumentView(documentType: .terms)
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationStack {
                LegalDocumentView(documentType: .privacy)
            }
        }
    }

    // MARK: - Computed Properties

    private var availablePrimaryPackages: [PaywallPackageDisplay] {
        subscriptionManager.paywallPackages
    }

    private var selectedPackage: PaywallPackageDisplay? {
        let packages = availablePrimaryPackages

        if let selected = packages.first(where: { $0.packageIdentifier == selectedPackageIdentifier }) {
            return selected
        }

        if let annual = packages.first(where: { $0.packageIdentifier == "$rc_annual" }) {
            return annual
        }

        return packages.first
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

    private func pricingOptionsSection(packages: [PaywallPackageDisplay]) -> some View {
        VStack(spacing: 12) {
            if packages.count > 1 {
                HStack(spacing: 10) {
                    ForEach(packages) { package in
                        pricingOptionCard(
                            package: package,
                            isSelected: package.packageIdentifier == selectedPackage?.packageIdentifier
                        )
                    }
                }
            } else if let package = packages.first {
                pricingOptionCard(
                    package: package,
                    isSelected: package.packageIdentifier == selectedPackage?.packageIdentifier
                )
            }
        }
    }

    private func pricingOptionCard(package: PaywallPackageDisplay, isSelected: Bool) -> some View {
        Button {
            selectedPackageIdentifier = package.packageIdentifier
            HapticManager.shared.impact(style: .light)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.planTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.appText)

                        if let trialText = package.trialText {
                            Text(trialText.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.appPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }

                    Spacer(minLength: 4)

                    selectionIndicator(isSelected: isSelected)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(package.localizedPrice)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.appText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(package.billingPeriodSuffix)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.appTextSecondary)
                    }

                    Text(package.summaryText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savingsText = package.savingsBadgeText {
                    Text(savingsText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.appPrimary)
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Flexible")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.appCard.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.appCard : Color.appCard.opacity(0.68))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected ? Color.appPrimary : Color.appBorder.opacity(0.75),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? Color.appPrimary.opacity(0.18) : .clear, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(package.planTitle) plan")
        .accessibilityHint(isSelected ? "Selected" : "Double tap to select this plan")
        .accessibilityIdentifier("paywall_plan_\(package.accessibilityIdentifierSuffix)")
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(isSelected ? .appPrimary : .appTextSecondary.opacity(0.65))
    }

    private func purchaseButton(package: PaywallPackageDisplay) -> some View {
        Button {
            Task {
                AppServicePorts.analyticsTracker.track(
                    event: "purchase_start",
                    properties: [
                        "package_id": package.packageIdentifier
                    ]
                )

                let success = await subscriptionManager.purchase(packageIdentifier: package.packageIdentifier)
                if !success && subscriptionManager.errorMessage != nil {
                    showPurchaseError = true
                }

                AppServicePorts.analyticsTracker.track(
                    event: success ? "purchase_success" : "purchase_failed",
                    properties: [
                        "package_id": package.packageIdentifier
                    ]
                )
            }
        } label: {
            HStack(spacing: 12) {
                if !subscriptionManager.isPurchasing {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }

                Text(subscriptionManager.isPurchasing ? "Processing..." : package.purchaseButtonTitle)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appPrimary)
            .cornerRadius(16)
        }
        .disabled(subscriptionManager.isPurchasing)
        .accessibilityIdentifier("paywall_purchase_button")
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                let success = await subscriptionManager.restorePurchases()
                if success {
                    showRestoreSuccess = true
                } else if subscriptionManager.errorMessage != nil {
                    showRestoreError = true
                }

                AppServicePorts.analyticsTracker.track(
                    event: success ? "restore_success" : "restore_failed"
                )
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .disabled(subscriptionManager.isPurchasing)
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
        .disabled(subscriptionManager.isPurchasing)
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

    private func plansUnavailableState(
        cachedPackage: CachedPaywallOfferingDisplay.PackageDisplay?
    ) -> some View {
        VStack(spacing: 12) {
            Text("Subscription plans are unavailable")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.appText)

            if let cachedPackage {
                cachedPricingSummary(package: cachedPackage)
            }

            Text("Check your connection and retry. You can still restore a purchase or log out below.")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await loadOfferings()
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appCard)
                        .cornerRadius(12)
                }
                .disabled(isLoading)
                .accessibilityIdentifier("paywall_retry_offerings_button")

                Button {
                    contactSupportAboutUnavailablePlans()
                } label: {
                    Label("Contact Support", systemImage: "envelope")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appCard.opacity(0.45))
                        .cornerRadius(12)
                }
                .accessibilityLabel("Contact Support")
                .accessibilityHint("Opens an email to LogYourBody support.")
                .accessibilityIdentifier("paywall_contact_support_button")
            }
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

    private func cachedPricingSummary(package: CachedPaywallOfferingDisplay.PackageDisplay) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last loaded price")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(package.localizedPrice)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.appText)

                    Text(package.billingPeriod.isEmpty ? "" : "/\(package.billingPeriod)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            }

            Spacer(minLength: 8)

            if let trialText = package.trialText {
                Text(trialText.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appPrimary.opacity(0.8))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appCard.opacity(0.65))
        .cornerRadius(14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall_cached_pricing_card")
    }

    private func contactSupportAboutUnavailablePlans() {
        let subject = "Subscription plans unavailable"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Subscription%20plans%20unavailable"
        let body = "I cannot load subscription plans in the iOS app."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:support@logyourbody.com?subject=\(subject)&body=\(body)") {
            openURL(url)
        }
    }

    // MARK: - Functions

    private func loadOfferings() async {
        isLoading = true
        await subscriptionManager.fetchOfferings()
        isLoading = false

        if subscriptionManager.paywallPackages.isEmpty {
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
        .environmentObject(SubscriptionManager.shared)
}
