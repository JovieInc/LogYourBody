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
    var validationMessage: String?
    var helperText: String?
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?
    var accessibilityIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.textSecondary)
                .accessibilityHidden(true)

            // Input Field
            BaseTextField(
                text: $text,
                placeholder: placeholder.isEmpty ? label : placeholder,
                configuration: TextFieldConfiguration(
                    style: .custom(background: .clear, border: nil),
                    isSecure: isSecure,
                    showToggle: isSecure,
                    errorMessage: validationMessage,
                    helperText: helperText,
                    cornerRadius: theme.radius.input,
                    accessibilityLabel: label,
                    accessibilityIdentifier: accessibilityIdentifier,
                    messageAccessibilityIdentifier: accessibilityIdentifier.map { "\($0)_validation_message" }
                ),
                keyboardType: keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization,
                submitLabel: submitLabel,
                onSubmit: onSubmit
            )
            .systemBGlassSurface(
                cornerRadius: theme.radius.input,
                tint: theme.colors.text,
                tintOpacity: 0.03,
                borderColor: validationMessage == nil ? theme.colors.border : theme.colors.error,
                borderOpacity: validationMessage == nil ? 0.65 : 0.8
            )
            .disabled(isDisabled)
        }
    }
}

// MARK: - Auth input validation

enum AuthEmailValidator {
    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
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
