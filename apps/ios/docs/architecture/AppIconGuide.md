# App Icon Setup Guide

## Required Icon Sizes for iOS

You need to generate the following icon sizes from your base 1024x1024 icon:

### iPhone Icons
- 20pt: 40x40 (2x), 60x60 (3x)
- 29pt: 58x58 (2x), 87x87 (3x)
- 40pt: 80x80 (2x), 120x120 (3x)
- 60pt: 120x120 (2x), 180x180 (3x)

### iPad Icons
- 20pt: 20x20 (1x), 40x40 (2x)
- 29pt: 29x29 (1x), 58x58 (2x)
- 40pt: 40x40 (1x), 80x80 (2x)
- 76pt: 76x76 (1x), 152x152 (2x)
- 83.5pt: 167x167 (2x)

### App Store Icon
- 1024x1024 (1x)

## How to Add Icons in Xcode:

1. Open `Assets.xcassets` in Xcode
2. Click on `AppIcon`
3. Drag and drop the appropriate sized icons into each slot
4. Make sure all required sizes are filled

## Icon Design Guidelines:
- Use the purple color (#5E6AD2) as the primary color
- Keep the design simple and recognizable at small sizes
- Avoid text in the icon
- Use the fitness/strength training theme

## Temporary Icon:
The app currently has the apple-touch-icon.png (180x180) from the web app copied as a starting point.