//
// StandardTextField.swift
// LogYourBody
//
import SwiftUI

// MARK: - Search Field

struct SearchField: View {
    @FocusState private var isFocused: Bool

    @Binding var text: String
    let placeholder: String
    let onSearch: (() -> Void)?

    init(
        text: Binding<String>,
        placeholder: String = "Search",
        onSearch: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text) {
                onSearch?()
            }
            .font(.body)
            .foregroundColor(.primary)
            .focused($isFocused)

            if !text.isEmpty {
                Button(
                    action: { text = "" },
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appCard)
        .cornerRadius(999)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(isFocused ? Color.appPrimary : Color.clear, lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}
