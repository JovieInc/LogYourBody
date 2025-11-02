#!/usr/bin/env node

/**
 * Build script for iOS platform
 * Generates Swift code from design tokens using Style Dictionary
 */

const StyleDictionary = require('style-dictionary');
const path = require('path');

console.log('🍎 Building design tokens for iOS (SwiftUI)...\n');

// Load iOS configuration
const config = require('../config/style-dictionary.ios');

// Register custom format for Swift colors
StyleDictionary.registerFormat({
  name: 'custom/swift/colors',
  formatter: function({ dictionary }) {
    const tokens = dictionary.allTokens;

    return `//
// DesignTokens+Colors.swift
// Generated from design tokens - DO NOT EDIT
//
import SwiftUI

extension DesignTokens {
    public struct Color {
${tokens
  .filter(token => token.type === 'color')
  .map(token => {
    const name = token.name.replace(/^color-/, '').replace(/-/g, '_');
    return `        public static let ${name} = SwiftUI.Color(hex: "${token.value}")`;
  })
  .join('\n')}
    }
}

// MARK: - Color Extension for Hex Support
extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
`;
  }
});

// Register custom format for Swift spacing
StyleDictionary.registerFormat({
  name: 'custom/swift/spacing',
  formatter: function({ dictionary }) {
    const tokens = dictionary.allTokens;

    return `//
// DesignTokens+Spacing.swift
// Generated from design tokens - DO NOT EDIT
//
import SwiftUI

extension DesignTokens {
    public struct Spacing {
${tokens
  .filter(token => token.attributes.category === 'spacing')
  .map(token => {
    const name = token.name.replace(/^spacing-/, '').replace(/-/g, '_');
    return `        public static let ${name}: CGFloat = ${token.value}`;
  })
  .join('\n')}
    }
}
`;
  }
});

// Build iOS tokens
const sd = StyleDictionary.extend(config);
sd.buildAllPlatforms();

console.log('\n✅ iOS design tokens built successfully!');
console.log(`📦 Output: ${path.resolve(__dirname, '../build/ios/')}\n`);
