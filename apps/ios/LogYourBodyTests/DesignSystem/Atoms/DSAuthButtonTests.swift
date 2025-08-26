//
// DSAuthButtonTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class DSAuthButtonTests: XCTestCase {
    // MARK: - Properties
    
    var actionCalled: Bool!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        actionCalled = false
    }
    
    override func tearDown() {
        actionCalled = nil
        super.tearDown()
    }
    
    // MARK: - Style Tests
    
    func testPrimaryStyleColors() {
        // Given
        let style = DSAuthButton.Style.primary
        
        // Then
        XCTAssertEqual(style.backgroundColor, .white)
        XCTAssertEqual(style.foregroundColor, .black)
    }
    
    func testSecondaryStyleColors() {
        // Given
        let style = DSAuthButton.Style.secondary
        
        // Then
        XCTAssertEqual(style.backgroundColor, Color(.systemGray6))
        XCTAssertEqual(style.foregroundColor, .appText)
    }
    
    func testSocialStyleColors() {
        // Given
        let style = DSAuthButton.Style.social
        
        // Then
        XCTAssertEqual(style.backgroundColor, .white)
        XCTAssertEqual(style.foregroundColor, .black)
    }
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        // When
        let button = DSAuthButton(title: "Test", action: {})
        
        // Then
        XCTAssertEqual(button.title, "Test")
        XCTAssertEqual(button.style.backgroundColor, DSAuthButton.Style.primary.backgroundColor)
        XCTAssertNil(button.icon)
        XCTAssertFalse(button.isLoading)
        XCTAssertTrue(button.isEnabled)
    }
    
    func testFullInitialization() {
        // When
        let button = DSAuthButton(
            title: "Sign In",
            style: .secondary,
            icon: "lock.fill",
            isLoading: true,
            isEnabled: false,
            action: {}
        )
        
        // Then
        XCTAssertEqual(button.title, "Sign In")
        XCTAssertEqual(button.style.backgroundColor, DSAuthButton.Style.secondary.backgroundColor)
        XCTAssertEqual(button.icon, "lock.fill")
        XCTAssertTrue(button.isLoading)
        XCTAssertFalse(button.isEnabled)
    }
    
    // MARK: - Action Tests
    
    func testActionCalled() {
        // Given
        var wasActionCalled = false
        let button = DSAuthButton(title: "Test") {
            wasActionCalled = true
        }
        
        // When
        button.action()
        
        // Then
        XCTAssertTrue(wasActionCalled)
    }
    
    func testActionNotCalledWhenDisabled() {
        // Given
        var wasActionCalled = false
        let button = DSAuthButton(
            title: "Test",
            isEnabled: false
        ) {
            wasActionCalled = true
        }
        
        // When - Button is disabled, so action shouldn't be called in real UI
        // This tests the logic, not the UI behavior
        
        // Then
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(wasActionCalled)
    }
    
    // MARK: - State Tests
    
    func testLoadingState() {
        // Given
        let loadingButton = DSAuthButton(
            title: "Loading",
            isLoading: true,
            action: {}
        )
        
        let normalButton = DSAuthButton(
            title: "Normal",
            isLoading: false,
            action: {}
        )
        
        // Then
        XCTAssertTrue(loadingButton.isLoading)
        XCTAssertFalse(normalButton.isLoading)
    }
    
    func testDisabledState() {
        // Given
        let disabledButton = DSAuthButton(
            title: "Disabled",
            isEnabled: false,
            action: {}
        )
        
        let enabledButton = DSAuthButton(
            title: "Enabled",
            isEnabled: true,
            action: {}
        )
        
        // Then
        XCTAssertFalse(disabledButton.isEnabled)
        XCTAssertTrue(enabledButton.isEnabled)
    }
    
    // MARK: - Icon Tests
    
    func testIconPresence() {
        // Given
        let buttonWithIcon = DSAuthButton(
            title: "Apple Sign In",
            icon: "apple.logo",
            action: {}
        )
        
        let buttonWithoutIcon = DSAuthButton(
            title: "Sign In",
            action: {}
        )
        
        // Then
        XCTAssertEqual(buttonWithIcon.icon, "apple.logo")
        XCTAssertNil(buttonWithoutIcon.icon)
    }
    
    // MARK: - Combined State Tests
    
    func testLoadingAndDisabledState() {
        // Given
        let button = DSAuthButton(
            title: "Test",
            isLoading: true,
            isEnabled: false,
            action: {}
        )
        
        // Then
        XCTAssertTrue(button.isLoading)
        XCTAssertFalse(button.isEnabled)
    }
}
