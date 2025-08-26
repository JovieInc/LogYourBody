//
// BaseButtonTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class BaseButtonTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testButtonConfigurationDefaults() {
        let config = ButtonConfiguration()
        
        XCTAssertEqual(config.style.backgroundColor, Color.appPrimary)
        XCTAssertEqual(config.style.foregroundColor, Color.white)
        XCTAssertEqual(config.size.height, 48)
        XCTAssertFalse(config.isLoading)
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.fullWidth)
        XCTAssertNil(config.icon)
        XCTAssertEqual(config.iconPosition, .leading)
        XCTAssertEqual(config.hapticFeedback, .light)
    }
    
    func testButtonStyleVariants() {
        // Primary
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.primary.backgroundColor, .appPrimary)
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.primary.foregroundColor, .white)
        XCTAssertNil(ButtonConfiguration.ButtonStyleVariant.primary.borderColor)
        
        // Secondary
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.secondary.backgroundColor, .appPrimary.opacity(0.1))
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.secondary.foregroundColor, .appPrimary)
        XCTAssertNotNil(ButtonConfiguration.ButtonStyleVariant.secondary.borderColor)
        
        // Tertiary
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.tertiary.backgroundColor, .appCard)
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.tertiary.foregroundColor, .appText)
        XCTAssertNotNil(ButtonConfiguration.ButtonStyleVariant.tertiary.borderColor)
        
        // Destructive
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.destructive.backgroundColor, .red)
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.destructive.foregroundColor, .white)
        
        // Ghost
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.ghost.backgroundColor, .clear)
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.ghost.foregroundColor, .appPrimary)
        
        // Social
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.social.backgroundColor, .white)
        XCTAssertEqual(ButtonConfiguration.ButtonStyleVariant.social.foregroundColor, .black)
    }
    
    func testButtonSizeVariants() {
        // Small
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.small.height, 36)
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.small.fontSize, 14)
        
        // Medium
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.medium.height, 48)
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.medium.fontSize, 16)
        
        // Large
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.large.height, 56)
        XCTAssertEqual(ButtonConfiguration.ButtonSizeVariant.large.fontSize, 18)
        
        // Custom
        let customSize = ButtonConfiguration.ButtonSizeVariant.custom(
            height: 40,
            padding: EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20),
            fontSize: 15
        )
        XCTAssertEqual(customSize.height, 40)
        XCTAssertEqual(customSize.fontSize, 15)
    }
    
    func testCustomButtonStyle() {
        let customStyle = ButtonConfiguration.ButtonStyleVariant.custom(
            background: .orange,
            foreground: .purple
        )
        
        XCTAssertEqual(customStyle.backgroundColor, .orange)
        XCTAssertEqual(customStyle.foregroundColor, .purple)
        XCTAssertNil(customStyle.borderColor)
    }
    
    // MARK: - BaseIconButton Tests
    
    func testIconButtonStyles() {
        XCTAssertEqual(BaseIconButton.IconButtonStyle.filled.backgroundColor, .appCard)
        XCTAssertNil(BaseIconButton.IconButtonStyle.filled.borderColor)
        
        XCTAssertEqual(BaseIconButton.IconButtonStyle.outlined.backgroundColor, .clear)
        XCTAssertNotNil(BaseIconButton.IconButtonStyle.outlined.borderColor)
        
        XCTAssertEqual(BaseIconButton.IconButtonStyle.plain.backgroundColor, .clear)
        XCTAssertNil(BaseIconButton.IconButtonStyle.plain.borderColor)
    }
    
    // MARK: - Integration Tests
    
    func testButtonWithLoadingState() {
        var config = ButtonConfiguration()
        config.isLoading = true
        
        XCTAssertTrue(config.isLoading)
        // In real app, this would disable interaction and show progress indicator
    }
    
    func testButtonWithIcon() {
        var config = ButtonConfiguration()
        config.icon = "arrow.right"
        config.iconPosition = .trailing
        
        XCTAssertEqual(config.icon, "arrow.right")
        XCTAssertEqual(config.iconPosition, .trailing)
    }
    
    func testFullWidthButton() {
        var config = ButtonConfiguration()
        config.fullWidth = true
        
        XCTAssertTrue(config.fullWidth)
    }
}