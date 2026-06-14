//
// AuthFormField.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthFormField Molecule

struct AuthFormField: View {
    @Environment(\.theme)
    private var theme

    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.textSecondary)

            // Input Field
            BaseTextField(
                text: $text,
                placeholder: placeholder.isEmpty ? label : placeholder,
                configuration: TextFieldConfiguration(
                    style: .custom(background: .clear, border: nil),
                    isSecure: isSecure,
                    showToggle: isSecure,
                    cornerRadius: theme.radius.input
                ),
                keyboardType: keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization
            )
            .systemBGlassSurface(
                cornerRadius: theme.radius.input,
                tint: theme.colors.text,
                tintOpacity: 0.03,
                borderColor: theme.colors.border,
                borderOpacity: 0.65
            )
            .disabled(isDisabled)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AuthFormField(
            label: "Email",
            text: .constant(""),
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            autocapitalization: .never
        )

        AuthFormField(
            label: "Password",
            text: .constant(""),
            isSecure: true,
            textContentType: .password
        )

        AuthFormField(
            label: "Full Name",
            text: .constant("John Doe"),
            textContentType: .name
        )
    }
    .padding()
    .background(Color.appBackground)
}
