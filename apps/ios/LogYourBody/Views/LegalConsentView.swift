//
// LegalConsentView.swift
// LogYourBody
//
import SwiftUI

struct LegalConsentView: View {
    @Binding var isPresented: Bool
    let userId: String
    let onAccept: () async -> Void

    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
    @State private var isLoading = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

    private var canContinue: Bool {
        acceptedTerms && acceptedPrivacy && !isLoading
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture { } // Prevent dismissal by tapping background

            VStack(spacing: 0) {
                // Content
                VStack(spacing: 24) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Welcome to LogYourBody")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text("Please review and accept our terms")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 32)

                    // Checkboxes
                    VStack(spacing: 16) {
                        ConsentCheckbox(
                            isChecked: $acceptedTerms,
                            text: "I accept the ",
                            linkText: "Terms of Service",
                            url: nil,
                            onLinkTap: {
                                showTermsSheet = true
                            }
                        )

                        ConsentCheckbox(
                            isChecked: $acceptedPrivacy,
                            text: "I accept the ",
                            linkText: "Privacy Policy",
                            url: nil,
                            onLinkTap: {
                                showPrivacySheet = true
                            }
                        )
                    }
                    .padding(.horizontal, 24)

                    // Continue Button
                    Button(
                        action: {
                            Task {
                                isLoading = true
                                await onAccept()
                                isLoading = false
                                isPresented = false
                            }
                        },
                        label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Continue")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(canContinue ? .black : .white.opacity(0.5))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canContinue ? Color.white : Color.white.opacity(0.2))
                            .cornerRadius(12)
                            .animation(.easeInOut(duration: 0.2), value: canContinue)
                        }
                    )
                    .disabled(!canContinue)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .background(Color.black)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
}

struct ConsentCheckbox: View {
    @Binding var isChecked: Bool
    let text: String
    let linkText: String
    let url: URL?
    let onLinkTap: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Custom checkbox
            Button(
                action: {
                    isChecked.toggle()
                },
                label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isChecked ? Color.white : Color.clear)
                            )

                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
            )
            .buttonStyle(PlainButtonStyle())

            // Text with link
            HStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))

                Button(action: handleLinkTap) {
                    Text(linkText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .underline()
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()
        }
    }

    private func handleLinkTap() {
        if let onLinkTap {
            onLinkTap()
        } else if let url {
            openURL(url)
        }
    }
}

#Preview {
    LegalConsentView(
        isPresented: .constant(true),
        userId: "test_user",
        onAccept: { }
    )
}
