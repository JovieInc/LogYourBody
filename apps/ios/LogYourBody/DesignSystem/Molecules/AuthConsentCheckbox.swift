//
// AuthConsentCheckbox.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthConsentCheckbox Molecule

struct AuthConsentCheckbox: View {
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
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { isChecked.toggle() }, label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isChecked ? .appPrimary : .appBorder)
            })
            .buttonStyle(PlainButtonStyle())

            // Text with link
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("I agree to the")
                        .font(.system(size: 14))
                        .foregroundColor(.appTextSecondary)

                    Button(action: handleLinkTap) {
                        Text(linkText)
                            .font(.system(size: 14))
                            .foregroundColor(.appPrimary)
                            .underline()
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .multilineTextAlignment(.leading)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextTertiary)
                    .multilineTextAlignment(.leading)
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
