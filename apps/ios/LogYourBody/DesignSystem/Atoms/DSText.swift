//
// DSText.swift
// LogYourBody
//
import SwiftUI

// MARK: - Design System Text Atom

struct DSText: View {
    let text: String
    let style: Font.TextStyle
    let weight: Font.Weight
    let color: Color
    
    init(
        _ text: String,
        style: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        color: Color = .appText
    ) {
        self.text = text
        self.style = style
        self.weight = weight
        self.color = color
    }
    
    var body: some View {
        Text(text)
            .font(.system(style).weight(weight))
            .foregroundColor(color)
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        DSText("Large Title", style: .largeTitle, weight: .bold)
        DSText("Title", style: .title, weight: .semibold)
        DSText("Headline", style: .headline, weight: .medium)
        DSText("Body Text", style: .body)
        DSText("Caption", style: .caption, color: .appTextSecondary)
        DSText("Error Text", style: .body, color: .error)
    }
    .padding()
    .background(Color.appBackground)
}
