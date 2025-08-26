//
// ErrorStateViewTests.swift
// LogYourBodyTests
//
// Comprehensive unit tests for ErrorStateView molecule
// Following atomic design principles and XCTest best practices
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class ErrorStateViewTests: XCTestCase {
    // MARK: - Properties
    
    var actionCallCount: Int!
    var lastActionTimestamp: Date?
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        actionCallCount = 0
        lastActionTimestamp = nil
    }
    
    override func tearDown() {
        actionCallCount = nil
        lastActionTimestamp = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        // Given
        let title = "Test Error"
        var actionCalled = false
        
        // When
        let errorView = ErrorStateView(
            title: title,
            buttonAction: { actionCalled = true }
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "exclamationmark.triangle")
        XCTAssertEqual(errorView.title, title)
        XCTAssertNil(errorView.message)
        XCTAssertEqual(errorView.buttonTitle, "Try Again")
        
        // Test action
        errorView.buttonAction()
        XCTAssertTrue(actionCalled)
    }
    
    func testFullInitialization() {
        // Given
        let icon = "wifi.slash"
        let title = "Network Error"
        let message = "Check your connection"
        let buttonTitle = "Retry"
        var actionCalled = false
        
        // When
        let errorView = ErrorStateView(
            icon: icon,
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            buttonAction: { actionCalled = true }
        )
        
        // Then
        XCTAssertEqual(errorView.icon, icon)
        XCTAssertEqual(errorView.title, title)
        XCTAssertEqual(errorView.message, message)
        XCTAssertEqual(errorView.buttonTitle, buttonTitle)
        
        // Test action
        errorView.buttonAction()
        XCTAssertTrue(actionCalled)
    }
    
    // MARK: - Action Tests
    
    func testButtonAction() {
        // Given
        var actionCalled = false
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: {
                actionCalled = true
            }
        )
        
        // When
        errorView.buttonAction()
        
        // Then
        XCTAssertTrue(actionCalled)
    }
    
    func testMultipleActionCalls() {
        // Given
        var callCount = 0
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: {
                callCount += 1
            }
        )
        
        // When
        errorView.buttonAction()
        errorView.buttonAction()
        errorView.buttonAction()
        
        // Then
        XCTAssertEqual(callCount, 3)
    }
    
    func testActionWithSideEffects() {
        // Given
        var sideEffectValue = ""
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: {
                sideEffectValue = "Action executed"
            }
        )
        
        // When
        errorView.buttonAction()
        
        // Then
        XCTAssertEqual(sideEffectValue, "Action executed")
    }
    
    func testActionClosure() {
        // Given
        let expectation = self.expectation(description: "Action should be called")
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: {
                expectation.fulfill()
            }
        )
        
        // When
        errorView.buttonAction()
        
        // Then
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // MARK: - Different State Tests
    
    func testNetworkErrorState() {
        // Given
        var retryCount = 0
        let errorView = ErrorStateView(
            icon: "wifi.slash",
            title: "No Internet Connection",
            message: "Please check your connection and try again.",
            buttonTitle: "Retry",
            buttonAction: { retryCount += 1 }
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "wifi.slash")
        XCTAssertEqual(errorView.title, "No Internet Connection")
        XCTAssertEqual(errorView.message, "Please check your connection and try again.")
        XCTAssertEqual(errorView.buttonTitle, "Retry")
        
        // Test retry action
        errorView.buttonAction()
        XCTAssertEqual(retryCount, 1)
    }
    
    func testGenericErrorState() {
        // Given
        let errorView = ErrorStateView(
            title: "Something went wrong",
            buttonAction: {}
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "exclamationmark.triangle")
        XCTAssertEqual(errorView.title, "Something went wrong")
        XCTAssertNil(errorView.message)
        XCTAssertEqual(errorView.buttonTitle, "Try Again")
    }
    
    func testLoadingErrorState() {
        // Given
        var reloadCalled = false
        let errorView = ErrorStateView(
            icon: "arrow.clockwise",
            title: "Failed to load",
            message: "The content couldn't be loaded.",
            buttonTitle: "Reload",
            buttonAction: { reloadCalled = true }
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "arrow.clockwise")
        XCTAssertEqual(errorView.title, "Failed to load")
        XCTAssertEqual(errorView.message, "The content couldn't be loaded.")
        XCTAssertEqual(errorView.buttonTitle, "Reload")
        
        // Test reload action
        errorView.buttonAction()
        XCTAssertTrue(reloadCalled)
    }
    
    func testPermissionErrorState() {
        // Given
        var settingsOpened = false
        let errorView = ErrorStateView(
            icon: "lock.fill",
            title: "Permission Denied",
            message: "Please grant the required permissions in Settings.",
            buttonTitle: "Open Settings",
            buttonAction: { settingsOpened = true }
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "lock.fill")
        XCTAssertEqual(errorView.title, "Permission Denied")
        XCTAssertEqual(errorView.message, "Please grant the required permissions in Settings.")
        XCTAssertEqual(errorView.buttonTitle, "Open Settings")
        
        // Test settings action
        errorView.buttonAction()
        XCTAssertTrue(settingsOpened)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStrings() {
        // Given
        let errorView = ErrorStateView(
            icon: "",
            title: "",
            message: "",
            buttonTitle: "",
            buttonAction: {}
        )
        
        // Then
        XCTAssertEqual(errorView.icon, "")
        XCTAssertEqual(errorView.title, "")
        XCTAssertEqual(errorView.message, "")
        XCTAssertEqual(errorView.buttonTitle, "")
    }
    
    func testLongStrings() {
        // Given
        let longTitle = "This is a very long error title that might wrap on smaller screens"
        let longMessage = "This is an extremely long error message that provides detailed information about what went wrong and how the user might be able to fix it. It could span multiple lines on most devices."
        let errorView = ErrorStateView(
            title: longTitle,
            message: longMessage,
            buttonAction: {}
        )
        
        // Then
        XCTAssertEqual(errorView.title, longTitle)
        XCTAssertEqual(errorView.message, longMessage)
    }
    
    // MARK: - Performance Tests
    
    func testInitializationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = ErrorStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: "Test message",
                    buttonTitle: "Retry",
                    buttonAction: {}
                )
            }
        }
    }
    
    func testActionPerformance() {
        // Given
        var counter = 0
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: { counter += 1 }
        )
        
        // When/Then
        measure {
            for _ in 0..<1_000 {
                errorView.buttonAction()
            }
        }
        
        XCTAssertEqual(counter, 1_000)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentActions() {
        // Given
        var counter = 0
        let lock = NSLock()
        let errorView = ErrorStateView(
            title: "Error",
            buttonAction: {
                lock.lock()
                counter += 1
                lock.unlock()
            }
        )
        
        let expectation = self.expectation(description: "All actions completed")
        let iterations = 100
        
        // When
        DispatchQueue.global().async {
            let group = DispatchGroup()
            
            for _ in 0..<iterations {
                group.enter()
                DispatchQueue.global().async {
                    errorView.buttonAction()
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                expectation.fulfill()
            }
        }
        
        // Then
        waitForExpectations(timeout: 5.0) { _ in
            XCTAssertEqual(counter, iterations)
        }
    }
}
