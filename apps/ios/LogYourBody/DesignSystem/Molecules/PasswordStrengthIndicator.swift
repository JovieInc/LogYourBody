//
// PasswordStrengthIndicator.swift
// LogYourBody
//
import SwiftUI

// MARK: - PasswordStrengthIndicator Molecule

struct PasswordStrengthIndicator: View {
    let password: String
    
    private var hasMinLength: Bool {
        password.count >= 8
    }
    
    private var hasUpperAndLower: Bool {
        password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
        password.rangeOfCharacter(from: .lowercaseLetters) != nil
    }
    
    private var hasNumberOrSymbol: Bool {
        password.rangeOfCharacter(from: .decimalDigits) != nil ||
        password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StrengthRow(
                isValid: hasMinLength,
                text: "At least 8 characters"
            )
            
            StrengthRow(
                isValid: hasUpperAndLower,
                text: "Mix of uppercase and lowercase letters"
            )
            
            StrengthRow(
                isValid: hasNumberOrSymbol,
                text: "At least one number or special character"
            )
        }
    }
}

// MARK: - Strength Row

private struct StrengthRow: View {
    let isValid: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(isValid ? .green : .appTextTertiary)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isValid ? .appTextSecondary : .appTextTertiary)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PasswordStrengthIndicator(password: "")
        
        PasswordStrengthIndicator(password: "short")
        
        PasswordStrengthIndicator(password: "longenough")
        
        PasswordStrengthIndicator(password: "LongEnough")
        
        PasswordStrengthIndicator(password: "LongEnough1!")
    }
    .padding()
    .background(Color.appBackground)
}
