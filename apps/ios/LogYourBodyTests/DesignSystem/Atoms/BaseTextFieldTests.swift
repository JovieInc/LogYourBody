//
// BaseTextFieldTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class BaseTextFieldTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testTextFieldConfigurationDefaults() {
        let config = TextFieldConfiguration()
        
        XCTAssertEqual(config.style.backgroundColor, Color(.systemGray6))
        XCTAssertFalse(config.hasIcon)
        XCTAssertNil(config.icon)
        XCTAssertFalse(config.isSecure)
        XCTAssertFalse(config.showToggle)
        XCTAssertNil(config.errorMessage)
        XCTAssertNil(config.helperText)
        XCTAssertNil(config.characterLimit)
        XCTAssertEqual(config.cornerRadius, 10)
        XCTAssertEqual(config.padding, EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }
    
    func testTextFieldStyles() {
        // Default style
        let defaultStyle = TextFieldConfiguration.TextFieldStyle.default
        XCTAssertEqual(defaultStyle.backgroundColor, Color(.systemGray6))
        XCTAssertNil(defaultStyle.borderColor)
        
        // Outlined style
        let outlinedStyle = TextFieldConfiguration.TextFieldStyle.outlined
        XCTAssertEqual(outlinedStyle.backgroundColor, .clear)
        XCTAssertEqual(outlinedStyle.borderColor, .appBorder)
        
        // Underlined style
        let underlinedStyle = TextFieldConfiguration.TextFieldStyle.underlined
        XCTAssertEqual(underlinedStyle.backgroundColor, .clear)
        XCTAssertEqual(underlinedStyle.borderColor, .appBorder)
        
        // Custom style
        let customStyle = TextFieldConfiguration.TextFieldStyle.custom(
            background: .blue.opacity(0.1),
            border: .blue
        )
        XCTAssertEqual(customStyle.backgroundColor, .blue.opacity(0.1))
        XCTAssertEqual(customStyle.borderColor, .blue)
    }
    
    func testEmailConfiguration() {
        let emailConfig = TextFieldConfiguration.email
        
        XCTAssertTrue(emailConfig.hasIcon)
        XCTAssertEqual(emailConfig.icon, "envelope")
        XCTAssertFalse(emailConfig.isSecure)
    }
    
    func testPasswordConfiguration() {
        let passwordConfig = TextFieldConfiguration.password
        
        XCTAssertTrue(passwordConfig.hasIcon)
        XCTAssertEqual(passwordConfig.icon, "lock")
        XCTAssertTrue(passwordConfig.isSecure)
        XCTAssertTrue(passwordConfig.showToggle)
    }
    
    func testSearchConfiguration() {
        let searchConfig = TextFieldConfiguration.search
        
        XCTAssertTrue(searchConfig.hasIcon)
        XCTAssertEqual(searchConfig.icon, "magnifyingglass")
        XCTAssertEqual(searchConfig.cornerRadius, 20)
    }
    
    // MARK: - State Tests
    
    func testCharacterLimitConfiguration() {
        var config = TextFieldConfiguration()
        config.characterLimit = 150
        
        XCTAssertEqual(config.characterLimit, 150)
    }
    
    func testErrorMessageConfiguration() {
        var config = TextFieldConfiguration()
        config.errorMessage = "Invalid email format"
        
        XCTAssertEqual(config.errorMessage, "Invalid email format")
        XCTAssertNil(config.helperText)
    }
    
    func testHelperTextConfiguration() {
        var config = TextFieldConfiguration()
        config.helperText = "Enter your full name"
        
        XCTAssertEqual(config.helperText, "Enter your full name")
        XCTAssertNil(config.errorMessage)
    }
    
    func testSecureFieldConfiguration() {
        var config = TextFieldConfiguration()
        config.isSecure = true
        config.showToggle = true
        
        XCTAssertTrue(config.isSecure)
        XCTAssertTrue(config.showToggle)
    }
}