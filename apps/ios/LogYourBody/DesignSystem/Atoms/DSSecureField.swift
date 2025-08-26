//
// DSSecureField.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSSecureField Atom
// Legacy wrapper for BaseTextField - use BaseTextField directly for new code

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
