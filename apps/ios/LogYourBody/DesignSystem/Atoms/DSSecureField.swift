//
// DSSecureField.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSSecureField Atom
// Legacy wrapper for BaseTextField - use BaseTextField directly for new code

@available(*, deprecated, message: "Use BaseTextField with .password configuration instead. Example: BaseTextField(text: $password, placeholder: \"Password\", configuration: .password). See BaseTextField.swift for comprehensive password field examples with show/hide toggle.")
struct DSSecureField: View {
    @Binding var text: String
    let placeholder: String
    var textContentType: UITextContentType? = .password
    var isDisabled: Bool = false
    
    var body: some View {
        BaseTextField(
            text: $text,
            placeholder: placeholder,
            configuration: .password,
            textContentType: textContentType
        )
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DSSecureField(
            text: .constant(""),
            placeholder: "Password"
        )
        
        DSSecureField(
            text: .constant("myPassword123"),
            placeholder: "Password"
        )
        
        DSSecureField(
            text: .constant("Disabled"),
            placeholder: "Disabled Field",
            isDisabled: true
        )
    }
    .padding()
    .background(Color.appBackground)
}
