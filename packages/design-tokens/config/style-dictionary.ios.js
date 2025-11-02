/**
 * Style Dictionary Configuration for iOS (SwiftUI)
 * Generates Swift code from design tokens
 */

module.exports = {
  source: [
    'tokens/core/**/*.json',
    'tokens/semantic/**/*.json',
    'tokens/platform/ios.json'
  ],
  platforms: {
    ios: {
      transformGroup: 'ios',
      buildPath: 'build/ios/',
      transforms: [
        'attribute/cti',
        'name/ti/camel',
        'color/UIColor',
        'content/swift/literal',
        'asset/swift/literal',
        'size/swift/remToCGFloat',
        'font/swift/literal'
      ],
      files: [
        {
          destination: 'DesignTokens.swift',
          format: 'ios-swift/class.swift',
          className: 'DesignTokens',
          filter: (token) => {
            // Filter out tokens that don't make sense for iOS
            return !token.path.includes('easing') || token.value !== 'linear';
          }
        }
      ],
      actions: ['copy_assets']
    },
    'ios-swift': {
      transformGroup: 'ios-swift',
      buildPath: 'build/ios/',
      files: [
        {
          destination: 'DesignTokens+Colors.swift',
          format: 'custom/swift/colors',
          filter: {
            attributes: {
              category: 'color'
            }
          }
        },
        {
          destination: 'DesignTokens+Spacing.swift',
          format: 'custom/swift/spacing',
          filter: {
            attributes: {
              category: 'spacing'
            }
          }
        },
        {
          destination: 'DesignTokens+Typography.swift',
          format: 'custom/swift/typography',
          filter: {
            attributes: {
              category: 'font'
            }
          }
        }
      ]
    }
  }
};
