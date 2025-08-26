//
// OTPField.swift
// LogYourBody
//
import SwiftUI

// MARK: - OTPField Molecule

struct OTPField: View {
    @Binding var code: String
    let length: Int
    let onComplete: ((String) -> Void)?
    
    @FocusState private var isFieldFocused: Bool
    
    init(
        code: Binding<String>,
        length: Int = 6,
        onComplete: ((String) -> Void)? = nil
    ) {
        self._code = code
        self.length = length
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            // Hidden TextField
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                .opacity(0)
                .onChange(of: code) { newValue in
                    // Limit to specified length
                    if newValue.count > length {
                        code = String(newValue.prefix(length))
                    }
                    
                    // Call completion handler
                    if newValue.count == length {
                        onComplete?(newValue)
                    }
                }
            
            // Visual OTP boxes
            HStack(spacing: 12) {
                ForEach(0..<length, id: \.self) { index in
                    OTPDigitBox(
                        digit: digitAt(index),
                        isActive: isFieldFocused && code.count == index
                    )
                }
            }
            .onTapGesture {
                isFieldFocused = true
            }
        }
    }
    
    private func digitAt(_ index: Int) -> String {
        if index < code.count {
            let codeIndex = code.index(code.startIndex, offsetBy: index)
            return String(code[codeIndex])
        }
        return ""
    }
}

// MARK: - OTP Digit Box

private struct OTPDigitBox: View {
    let digit: String
    let isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.appPrimary : Color.appBorder, lineWidth: 1)
                )
                .frame(width: 46, height: 56)
            
            Text(digit)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.appText)
            
            if isActive {
                Rectangle()
                    .fill(Color.appPrimary)
                    .frame(width: 2, height: 24)
                    .opacity(digit.isEmpty ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        OTPField(code: .constant(""))
        
        OTPField(code: .constant("123"))
        
        OTPField(code: .constant("123456"))
        
        OTPField(code: .constant("1234"), length: 4)
    }
    .padding()
    .background(Color.appBackground)
}
