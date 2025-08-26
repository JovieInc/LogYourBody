//
// AuthFormField.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthFormField Molecule

struct AuthFormField: View {
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
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)
            
            // Input Field
            if isSecure {
                DSSecureField(
                    text: $text,
                    placeholder: placeholder.isEmpty ? label : placeholder,
                    textContentType: textContentType,
                    isDisabled: isDisabled
                )
            } else {
                DSTextField(
                    text: $text,
                    placeholder: placeholder.isEmpty ? label : placeholder,
                    keyboardType: keyboardType,
                    textContentType: textContentType,
                    autocapitalization: autocapitalization,
                    isDisabled: isDisabled
                )
            }
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
