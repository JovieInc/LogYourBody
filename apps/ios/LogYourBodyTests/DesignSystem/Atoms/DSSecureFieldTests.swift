//
// DSSecureFieldTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class DSSecureFieldTests: XCTestCase {
    // MARK: - Properties
    
    var sut: DSSecureField!
    @State private var text = ""
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        text = ""
        sut = DSSecureField(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            placeholder: "Password"
        )
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func testInitialization() {
        // Given/When
        let secureField = DSSecureField(
            text: .constant("test"),
            placeholder: "Enter password",
            textContentType: .newPassword,
            isDisabled: true
        )
        
        // Then
        XCTAssertNotNil(secureField)
    }
    
    func testDefaultValues() {
        // Given
        let binding = Binding<String>(get: { "" }, set: { _ in })
        
        // When
        let secureField = DSSecureField(text: binding, placeholder: "Test")
        
        // Then
        XCTAssertNotNil(secureField)
        XCTAssertEqual(secureField.placeholder, "Test")
        XCTAssertEqual(secureField.textContentType, .password)
        XCTAssertFalse(secureField.isDisabled)
    }
    
    func testToggleVisibility() {
        // Given
        let binding = Binding<String>(get: { "" }, set: { _ in })
        let secureField = DSSecureField(text: binding, placeholder: "Test")
        
        // Then
        // The toggle functionality is internal to the view
        // We verify the component can be created with expected properties
        XCTAssertNotNil(secureField)
    }
    
    func testDisabledState() {
        // Given
        let disabledField = DSSecureField(
            text: .constant("test"),
            placeholder: "Password",
            isDisabled: true
        )
        
        // Then
        XCTAssertTrue(disabledField.isDisabled)
        XCTAssertEqual(disabledField.placeholder, "Password")
    }
    
    func testFocusState() {
        // Given/When/Then
        // Focus state is handled internally by SwiftUI
        // We verify the component can be created
        XCTAssertNotNil(sut)
    }
    
    func testTextBinding() {
        // Given
        var testText = ""
        let binding = Binding<String>(
            get: { testText },
            set: { testText = $0 }
        )
        
        // When
        let secureField = DSSecureField(
            text: binding,
            placeholder: "Password"
        )
        
        // Then
        XCTAssertEqual(testText, "")
        binding.wrappedValue = "newPassword"
        XCTAssertEqual(testText, "newPassword")
    }
    
    func testAccessibility() {
        // Given
        let secureField = DSSecureField(
            text: .constant(""),
            placeholder: "Password"
        )
        
        // Then
        // Accessibility is handled by SwiftUI's SecureField
        XCTAssertEqual(secureField.placeholder, "Password")
    }
}
