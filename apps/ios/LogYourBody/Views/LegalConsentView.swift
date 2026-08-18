//
// LegalConsentView.swift
// LogYourBody
//
import SwiftUI

enum LegalConsentPolicy {
    static func canContinue(
        acceptedTerms: Bool,
        acceptedPrivacy: Bool,
        isLoading: Bool
    ) -> Bool {
        acceptedTerms && acceptedPrivacy && !isLoading
    }
}

struct LegalConsentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isPresented: Bool
    let userId: String
    let onAccept: () async -> Void

    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
    @State private var isLoading = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

    private var canContinue: Bool {
        LegalConsentPolicy.canContinue(
            acceptedTerms: acceptedTerms,
            acceptedPrivacy: acceptedPrivacy,
            isLoading: isLoading
        )
    }

    var body: some View {
        ZStack {
            Color.jovieCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    header

                    VStack(spacing: JovieTokens.itemGap) {
                        LegalConsentCheckbox(
                            isChecked: $acceptedTerms,
                            agreement: "I accept the Terms of Service",
                            linkTitle: "Read Terms of Service",
                            linkHint: "Opens the Terms of Service.",
                            onLinkTap: { showTermsSheet = true }
                        )

                        LegalConsentCheckbox(
                            isChecked: $acceptedPrivacy,
                            agreement: "I accept the Privacy Policy",
                            linkTitle: "Read Privacy Policy",
                            linkHint: "Opens the Privacy Policy.",
                            onLinkTap: { showPrivacySheet = true }
                        )
                    }

                    Text("You can review these documents again in Settings.")
                        .font(.footnote)
                        .foregroundColor(.jovieTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, 48)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueAction
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
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
        .worldClassScreen(.legalConsent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your data stays yours.")
                .font(.title2.weight(.bold))
                .foregroundColor(.jovieText)

            Text(
                "We use the profile details, measurements, photos, and consent records you choose to provide. " +
                    "You can export or request deletion anytime."
            )
                .font(.body)
                .foregroundColor(.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var continueAction: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.jovieHairline)
                .frame(height: 1)

            BaseButton(
                "Continue",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    isLoading: isLoading,
                    isEnabled: canContinue,
                    fullWidth: true
                ),
                action: accept
            )
            .accessibilityIdentifier("legal_consent_continue_button")
            .accessibilityHint(
                canContinue
                    ? "Accepts the selected agreements and continues."
                    : "Accept both agreements to continue."
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.vertical, 12)
        }
        .background(Color.jovieCanvas.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private func accept() {
        guard canContinue else { return }

        isLoading = true
        Task { @MainActor in
            await onAccept()
            isLoading = false
            isPresented = false
        }
    }
}

private struct LegalConsentCheckbox: View {
    @Binding var isChecked: Bool
    let agreement: String
    let linkTitle: String
    let linkHint: String
    let onLinkTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: $isChecked) {
                EmptyView()
            }
            .labelsHidden()
            .tint(Color.jovieAction)
            .jovieTouchTarget()
            .accessibilityLabel(agreement)
            .accessibilityHint("Required to continue.")

            Button(action: onLinkTap) {
                Text(linkTitle)
                    .font(.body.weight(.medium))
                    .foregroundColor(.jovieText)
                    .underline()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .jovieTouchTarget()
            .accessibilityHint(linkHint)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    LegalConsentView(
        isPresented: .constant(true),
        userId: "test_user",
        onAccept: { }
    )
}
