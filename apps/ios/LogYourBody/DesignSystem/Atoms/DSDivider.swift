//
// DSDivider.swift
// LogYourBody
//
import SwiftUI

// MARK: - Design System Divider Atom

struct DSDivider: View {
    private var inset: CGFloat = 0
    
    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
    
    func insetted(_ amount: CGFloat) -> DSDivider {
        var divider = self
        divider.inset = amount
        return divider
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Text("Full Width Divider")
        DSDivider()
        
        Text("Insetted Divider")
        DSDivider().insetted(16)
        
        Text("More Insetted Divider")
        DSDivider().insetted(32)
    }
    .padding()
    .background(Color.appBackground)
}
