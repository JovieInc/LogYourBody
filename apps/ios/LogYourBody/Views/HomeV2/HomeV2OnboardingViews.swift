//
// HomeV2OnboardingViews.swift
// LogYourBody
//
import SwiftUI

extension LegalDocumentView.LegalDocumentType: Identifiable {
    public var id: String { String(describing: self) }
}

enum HomeV2OnboardingCopy {
    static let brand = "LogYourBody"
    static let signInTitle = "See how you’re really doing."
    static let signInBody = "Weight, body fat and progress photos from Apple Health, on one timeline."
    static let continueWithApple = "Continue with Apple"
    static let openingApple = "Opening Apple…"
    static let legalPrefix = "By continuing you agree to the"
    static let terms = "Terms"
    static let privacy = "Privacy Policy"
    static let included = [
        "Unlimited progress photos and compare",
        "Body-fat, lean mass and FFMI trends",
        "Phase insights that tell you when to stop cutting"
    ]
}

/// Sign in (Pencil O1): the promise, one Apple action, the legal line.
struct HomeV2SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var legalDocument: LegalDocumentView.LegalDocumentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
                Text(HomeV2OnboardingCopy.brand)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Text(HomeV2OnboardingCopy.signInTitle)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .bold, relativeTo: .largeTitle)
                    .kerning(-1)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_sign_in")
                Text(HomeV2OnboardingCopy.signInBody)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText {
                Text(errorText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.red)
                    .padding(.top, HomeV2Tokens.Space.compact)
                    .accessibilityIdentifier("home_v2_sign_in_error")
            }

            AppleSignInActionButton(
                isLoading: $isLoading,
                identifier: "home_v2_sign_in_apple",
                onAttempt: {
                    errorText = nil
                    AppServicePorts.analyticsTracker.track(
                        event: "login_attempt",
                        properties: ["method": "apple"]
                    )
                },
                onFailure: { error in
                    errorText = authManager.loginErrorMessage(for: error)
                    AppServicePorts.analyticsTracker.track(
                        event: "login_failed",
                        properties: ["method": "apple"]
                    )
                },
                label: { isLoading in
                    HStack(spacing: HomeV2Tokens.Space.tight) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .semibold))
                        Text(isLoading ? HomeV2OnboardingCopy.openingApple : HomeV2OnboardingCopy.continueWithApple)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(HomeV2Tokens.Colors.ctaInk)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
                    .background(HomeV2Tokens.Colors.ctaFill, in: Capsule())
                    .contentShape(Capsule())
                }
            )
            .buttonStyle(.plain)
            .accessibilityHint("Starts Sign in with Apple through Jovie Better Auth.")
            .padding(.top, HomeV2Tokens.Space.margin)

            legalLine
                .padding(.top, HomeV2Tokens.Space.compact)
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .padding(.bottom, HomeV2Tokens.Space.margin)
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(documentType: document) }
        }
        .onAppear { AppServicePorts.analyticsTracker.track(event: "login_view") }
    }

    private var legalLine: some View {
        HStack(spacing: 4) {
            Text(HomeV2OnboardingCopy.legalPrefix)
            Button(HomeV2OnboardingCopy.terms) { legalDocument = .terms }
                .buttonStyle(.plain)
                .underline()
            Text("and")
            Button(HomeV2OnboardingCopy.privacy) { legalDocument = .privacy }
                .buttonStyle(.plain)
                .underline()
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
