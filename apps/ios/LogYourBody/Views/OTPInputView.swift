//
// OTPInputView.swift
// LogYourBody
//
import SwiftUI
import Combine

struct OTPInputView: View {
    @Binding var otpCode: String
    var numberOfDigits: Int = 6
    var onComplete: (() -> Void)?

    @State private var digits: [String] = []
    @FocusState private var focusedIndex: Int?
    @State private var cancellables = Set<AnyCancellable>()

    init(otpCode: Binding<String>, numberOfDigits: Int = 6, onComplete: (() -> Void)? = nil) {
        self._otpCode = otpCode
        self.numberOfDigits = numberOfDigits
        self.onComplete = onComplete

        // Initialize digits array
        _digits = State(initialValue: Array(repeating: "", count: numberOfDigits))
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<numberOfDigits, id: \.self) { index in
                SingleDigitInput(
                    digit: $digits[index],
                    isFocused: focusedIndex == index,
                    onTextChange: { newValue in
                        handleTextChange(at: index, newValue: newValue)
                    }
                )
                .focused($focusedIndex, equals: index)
                .onTapGesture {
                    focusedIndex = index
                }
            }
        }
        .onAppear {
            // Initialize digits if needed
            if digits.count != numberOfDigits {
                digits = Array(repeating: "", count: numberOfDigits)
            }

            // Focus first field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedIndex = 0
            }

            // Set up paste handling
            NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)
                .sink { _ in
                    handlePaste()
                }
                .store(in: &cancellables)
        }
        .onChange(of: digits) { _ in
            // Update the bound otpCode
            otpCode = digits.joined()

            // Check if all digits are filled
            if digits.count == numberOfDigits && digits.allSatisfy({ !$0.isEmpty }) {
                // Dismiss keyboard
                focusedIndex = nil
                // Call completion handler
                onComplete?()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in
            // Handle auto-fill from SMS
            if let pastedString = UIPasteboard.general.string,
               pastedString.count == numberOfDigits,
               pastedString.allSatisfy({ $0.isNumber }) {
                handlePastedCode(pastedString)
            }
        }
    }

    private func handleTextChange(at index: Int, newValue: String) {
        // Handle deletion
        if newValue.isEmpty {
            digits[index] = ""
            // Move focus to previous field if available
            if index > 0 {
                focusedIndex = index - 1
            }
            return
        }

        // Handle multi-character paste
        if newValue.count > 1 {
            handlePastedCode(newValue)
            return
        }

        // Handle single digit
        if newValue.count == 1 && newValue.last!.isNumber {
            digits[index] = String(newValue.last!)

            // Move to next field
            if index < numberOfDigits - 1 {
                focusedIndex = index + 1
            } else {
                // Last digit entered, dismiss keyboard
                focusedIndex = nil
            }
        }
    }

    private func handlePaste() {
        guard let pastedString = UIPasteboard.general.string else { return }
        handlePastedCode(pastedString)
    }

    private func handlePastedCode(_ code: String) {
        // Extract only numbers from the pasted string
        let numbers = code.filter { $0.isNumber }

        // Fill in the digits
        for (index, char) in numbers.prefix(numberOfDigits).enumerated() {
            digits[index] = String(char)
        }

        // Focus the next empty field or dismiss keyboard if all filled
        if let firstEmptyIndex = digits.firstIndex(where: { $0.isEmpty }) {
            focusedIndex = firstEmptyIndex
        } else {
            focusedIndex = nil
        }
    }
}

struct SingleDigitInput: View {
    @Binding var digit: String
    let isFocused: Bool
    let onTextChange: (String) -> Void

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor : Color.appBorder, lineWidth: 2)
                )
                .animation(.easeInOut(duration: 0.2), value: isFocused)

            // Hidden TextField for input
            TextField("", text: Binding(
                get: { digit },
                set: { newValue in
                    onTextChange(newValue)
                }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled(true)
            .frame(width: 50, height: 56)
            .multilineTextAlignment(.center)
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
            .foregroundColor(.clear)
            .accentColor(.clear)
            .background(Color.clear)

            // Visible digit
            Text(digit)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(.appText)
        }
        .frame(width: 50, height: 56)
    }
}

struct OTPInputView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            OTPInputView(otpCode: .constant(""))
        }
        .padding()
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }
}
