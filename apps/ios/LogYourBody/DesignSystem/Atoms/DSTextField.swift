//
// DSTextField.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSTextField Atom
// Legacy wrapper for BaseTextField - use BaseTextField directly for new code

@available(*, deprecated, message: "Use BaseTextField directly instead. DSTextField is a legacy wrapper that adds no value. See BaseTextField.swift for comprehensive examples including email, password, and search field configurations.")
struct DSTextField: View {
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isDisabled: Bool = false
    
    var body: some View {
        BaseTextField(
            text: $text,
            placeholder: placeholder,
            keyboardType: keyboardType,
            textContentType: textContentType,
            autocapitalization: autocapitalization
        )
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DSTextField(
            text: .constant(""),
            placeholder: "Email",
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            autocapitalization: .never
        )
        
        DSTextField(
            text: .constant("john@example.com"),
            placeholder: "Email"
        )
        
        DSTextField(
            text: .constant("Disabled"),
            placeholder: "Disabled Field",
            isDisabled: true
        )
    }
    .padding()
    .background(Color.appBackground)
}
