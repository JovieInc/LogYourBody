//
// AuthConsentCheckbox.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthConsentCheckbox Molecule

struct AuthConsentCheckbox: View {
    @Environment(\.theme)
    private var theme

    @Binding var isChecked: Bool
    let text: String
    let linkText: String
    let url: URL?
    let onLinkTap: (() -> Void)?

    @Environment(\.openURL) private var openURL

    init(
        isChecked: Binding<Bool>,
        text: String,
        linkText: String,
        url: URL? = nil,
        onLinkTap: (() -> Void)? = nil
    ) {
        _isChecked = isChecked
        self.text = text
        self.linkText = linkText
        self.url = url
        self.onLinkTap = onLinkTap
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: { isChecked.toggle() }, label: {
                Image(systemName: isChecked ? "checkmark" : "square")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundColor(isChecked ? .jovieActionText : theme.colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isChecked ? Color.jovieAction : Color.jovieSurfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isChecked ? Color.clear : Color.jovieHairline, lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Agree to \(linkText)")
            .accessibilityValue(isChecked ? "Selected" : "Not selected")
            .accessibilityHint("Required to create an account.")

            VStack(alignment: .leading, spacing: 0) {
                Text("I agree to the")
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
                    .accessibilityHidden(true)

                Button(action: handleLinkTap) {
                    Text(linkText)
                        .font(theme.typography.labelMedium)
                        .foregroundColor(.jovieText)
                        .underline()
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel("Read \(linkText)")
                .accessibilityHint(text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func handleLinkTap() {
        if let onLinkTap {
            onLinkTap()
        } else if let url {
            openURL(url)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AuthConsentCheckbox(
            isChecked: .constant(true),
            text: "LogYourBody's terms of service",
            linkText: "Terms of Service",
            url: nil
        )

        AuthConsentCheckbox(
            isChecked: .constant(false),
            text: "How we handle your data",
            linkText: "Privacy Policy",
            url: nil
        )

        AuthConsentCheckbox(
            isChecked: .constant(false),
            text: "Important health information",
            linkText: "Health Disclaimer",
            url: nil
        )
    }
    .padding()
    .background(Color.appBackground)
}
