//
// PaywallView.swift
// LogYourBody
//
// One compact, trust-first subscription surface. Pricing is shown only when the
// currently loaded offering is available; stale partial offers are never reused
// as a purchase proposition.
//
import SwiftUI

struct PaywallView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

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
            theme.colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: JovieTokens.sectionGap) {
                    header
                    valueProposition

                    if !availablePrimaryPackages.isEmpty {
                        pricingOptions
                    } else if isLoading {
                        ProgressView("Loading plans…")
                            .tint(theme.colors.text)
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 96)
                    } else {
                        plansUnavailableState
                    }

                    if let package = selectedPackage {
                        purchaseButton(package: package)
                    }

                    recoveryActions
                    legalLinks
                }
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, JovieTokens.sectionGap)
                .padding(.bottom, JovieTokens.sectionGap)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("paywall_screen")

            if subscriptionManager.isPurchasing {
                LoadingOverlay(message: "Processing purchase…")
            }
        }
        .alert("Purchase Error", isPresented: $showPurchaseError) {
            Button("OK", role: .cancel) { subscriptionManager.errorMessage = nil }
        } message: {
            Text(subscriptionManager.errorMessage ?? "An error occurred")
        }
        .alert("Restore Successful", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your subscription has been restored.")
        }
        .alert("No Subscription Found", isPresented: $showRestoreError) {
            Button("OK", role: .cancel) { subscriptionManager.errorMessage = nil }
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
        .task {
            if subscriptionManager.paywallPackages.isEmpty {
                await loadOfferings()
            } else {
                isLoading = false
            }
            AppServicePorts.analyticsTracker.track(event: "paywall_view")
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationStack { LegalDocumentView(documentType: .terms) }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationStack { LegalDocumentView(documentType: .privacy) }
        }
    }

    private var availablePrimaryPackages: [PaywallPackageDisplay] {
        subscriptionManager.paywallPackages
    }

    private var selectedPackage: PaywallPackageDisplay? {
        availablePrimaryPackages.first { $0.packageIdentifier == selectedPackageIdentifier }
            ?? availablePrimaryPackages.first { $0.packageIdentifier == "$rc_annual" }
            ?? availablePrimaryPackages.first
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.colors.text)
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.colors.text.opacity(0.08)))

            Text("LogYourBody Pro")
                .font(theme.typography.headlineLarge)
                .foregroundStyle(theme.colors.text)
                .accessibilityIdentifier("paywall_title")

            Text("A clear, private view of your progress.")
                .font(theme.typography.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var valueProposition: some View {
        Text("Log quickly. See weight, body fat, FFMI, and your trend in one place.")
            .font(theme.typography.bodyMedium)
            .foregroundStyle(theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var pricingOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JovieTokens.itemGap) {
                ForEach(availablePrimaryPackages) { package in
                    pricingOption(package)
                        .frame(minWidth: 156)
                }
            }

            VStack(spacing: JovieTokens.itemGap) {
                ForEach(availablePrimaryPackages) { package in
                    pricingOption(package)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pricingOption(_ package: PaywallPackageDisplay) -> some View {
        let isSelected = package.packageIdentifier == selectedPackage?.packageIdentifier

        return Button {
            selectedPackageIdentifier = package.packageIdentifier
            HapticManager.shared.impact(style: .light)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(package.planTitle)
                        .font(theme.typography.labelLarge)
                        .foregroundStyle(theme.colors.text)

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(.headline, design: .default).weight(.semibold))
                        .foregroundStyle(isSelected ? theme.colors.text : theme.colors.textTertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(package.localizedPrice)
                        .font(theme.typography.displaySmall)
                        .foregroundStyle(theme.colors.text)
                        .monospacedDigit()

                    Text(package.billingPeriodSuffix)
                        .font(theme.typography.bodySmall)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Text(package.summaryText)
                    .font(theme.typography.captionLarge)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let savingsText = package.savingsBadgeText {
                    Text(savingsText)
                        .font(theme.typography.labelSmall)
                        .foregroundStyle(theme.colors.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(theme.colors.text))
                } else if let trialText = package.trialText {
                    Text(trialText)
                        .font(theme.typography.labelSmall)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(16)
            .systemBGlassSurface(
                cornerRadius: JovieTokens.cardRadius,
                tint: theme.colors.text,
                tintOpacity: isSelected ? 0.08 : 0.03,
                borderColor: isSelected ? theme.colors.text : theme.colors.border,
                borderOpacity: isSelected ? 0.62 : 0.6,
                borderWidth: isSelected ? 1.5 : 1,
                shadowOpacity: isSelected ? 0.12 : 0.04,
                shadowRadius: isSelected ? 14 : 8,
                shadowY: 5
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(package.planTitle) plan")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this plan")
        .accessibilityIdentifier("paywall_plan_\(package.accessibilityIdentifierSuffix)")
    }

    private func purchaseButton(package: PaywallPackageDisplay) -> some View {
        BaseButton(
            subscriptionManager.isPurchasing ? "Processing…" : package.purchaseButtonTitle,
            configuration: ButtonConfiguration(
                style: .custom(background: .jovieAction, foreground: .jovieActionText),
                size: .large,
                isLoading: subscriptionManager.isPurchasing,
                isEnabled: !subscriptionManager.isPurchasing,
                fullWidth: true,
                icon: subscriptionManager.isPurchasing ? nil : "checkmark",
                iconPosition: .leading,
                cornerRadius: 9_999
            ),
            action: {
                Task { await purchase(package) }
            }
        )
        .accessibilityIdentifier("paywall_purchase_button")
    }

    private var plansUnavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plans are temporarily unavailable", systemImage: "wifi.exclamationmark")
                .font(theme.typography.labelLarge)
                .foregroundStyle(theme.colors.text)
                .accessibilityIdentifier("paywall_plans_unavailable_state")

            Text("Check your connection and try again. You can still restore a previous purchase or switch accounts.")
                .font(theme.typography.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            unavailablePlanActions
        }
        .padding(16)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.cardRadius,
            tint: theme.colors.text,
            tintOpacity: 0.035,
            borderColor: theme.colors.border,
            borderOpacity: 0.65,
            shadowOpacity: 0.06,
            shadowRadius: 10,
            shadowY: 4
        )
    }

    private var unavailablePlanActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                retryOfferingsButton
                contactSupportButton
            }

            VStack(spacing: 8) {
                retryOfferingsButton
                contactSupportButton
            }
        }
    }

    private var retryOfferingsButton: some View {
        Button {
            Task { await loadOfferings() }
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(theme.typography.labelLarge)
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                        .fill(theme.colors.text.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                        .stroke(theme.colors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("Retry loading subscription plans")
        .accessibilityHint("Attempts to load the available subscription plans again.")
        .accessibilityIdentifier("paywall_retry_offerings_button")
    }

    private var contactSupportButton: some View {
        Button(action: contactSupportAboutUnavailablePlans) {
            Label("Contact support", systemImage: "envelope")
                .font(theme.typography.labelLarge)
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact support")
        .accessibilityHint("Opens email support for unavailable subscription plans.")
        .accessibilityIdentifier("paywall_contact_support_button")
    }

    private var recoveryActions: some View {
        VStack(spacing: 4) {
            Button {
                Task { await restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .font(theme.typography.labelLarge)
                    .foregroundStyle(theme.colors.text)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .disabled(subscriptionManager.isPurchasing)
            .accessibilityIdentifier("paywall_restore_purchases_button")

            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(theme.typography.labelMedium)
                    .foregroundStyle(theme.colors.error)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .disabled(subscriptionManager.isPurchasing)
            .accessibilityIdentifier("paywall_logout_button")
        }
    }

    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                termsButton
                Text("•").foregroundStyle(theme.colors.textTertiary)
                privacyButton
            }

            VStack(spacing: 2) {
                termsButton
                privacyButton
            }
        }
        .font(theme.typography.captionLarge)
    }

    private var termsButton: some View {
        Button("Terms of Service") { showTermsSheet = true }
            .foregroundStyle(theme.colors.textSecondary)
            .frame(minHeight: JovieTokens.minimumHitTarget)
    }

    private var privacyButton: some View {
        Button("Privacy Policy") { showPrivacySheet = true }
            .foregroundStyle(theme.colors.textSecondary)
            .frame(minHeight: JovieTokens.minimumHitTarget)
    }

    private func purchase(_ package: PaywallPackageDisplay) async {
        AppServicePorts.analyticsTracker.track(
            event: "purchase_start",
            properties: ["package_id": package.packageIdentifier]
        )

        let success = await subscriptionManager.purchase(packageIdentifier: package.packageIdentifier)
        if !success, subscriptionManager.errorMessage != nil {
            showPurchaseError = true
        }

        AppServicePorts.analyticsTracker.track(
            event: success ? "purchase_success" : "purchase_failed",
            properties: ["package_id": package.packageIdentifier]
        )
    }

    private func restorePurchases() async {
        let success = await subscriptionManager.restorePurchases()
        if success {
            showRestoreSuccess = true
        } else if subscriptionManager.errorMessage != nil {
            showRestoreError = true
        }
        AppServicePorts.analyticsTracker.track(event: success ? "restore_success" : "restore_failed")
    }

    private func contactSupportAboutUnavailablePlans() {
        let subject = "Subscription plans unavailable"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Subscription%20plans%20unavailable"
        let body = "I cannot load subscription plans in the iOS app."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:support@logyourbody.com?subject=\(subject)&body=\(body)") else {
            return
        }
        openURL(url)
    }

    private func loadOfferings() async {
        isLoading = true
        await subscriptionManager.fetchOfferings()
        isLoading = false
    }
}

#Preview {
    PaywallView()
        .environmentObject(AuthManager())
        .environmentObject(SubscriptionManager.shared)
}
