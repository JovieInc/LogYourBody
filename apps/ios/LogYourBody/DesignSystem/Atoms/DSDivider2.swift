//
// Divider.swift
// LogYourBody
//
import SwiftUI

// MARK: - Atom: Custom Divider

struct DSDivider: View {
    let inset: CGFloat
    let color: Color
    let thickness: CGFloat
    
    init(
        inset: CGFloat = 0,
        color: Color? = nil,
        thickness: CGFloat = 0.5
    ) {
        self.inset = inset
        self.color = color ?? DesignSystem.colors.border
        self.thickness = thickness
    }
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: thickness)
            .padding(.leading, inset)
    }
}

// MARK: - Convenience Modifiers

extension DSDivider {
    func insetted(_ amount: CGFloat = 16) -> DSDivider {
        DSDivider(inset: amount, color: color, thickness: thickness)
    }
    
    func colored(_ color: Color) -> DSDivider {
        DSDivider(inset: inset, color: color, thickness: thickness)
    }
}

#Preview {
    VStack(spacing: 20) {
        DSDivider()
        DSDivider().insetted()
        DSDivider().insetted(40)
        DSDivider().colored(.red)
    }
    .padding()
    .background(Color.black)
}
