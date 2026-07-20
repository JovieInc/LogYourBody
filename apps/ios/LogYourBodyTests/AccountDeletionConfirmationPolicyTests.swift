import XCTest
@testable import LogYourBody

final class AccountDeletionConfirmationPolicyTests: XCTestCase {
    func testConfirmationPhraseIsDelete() {
        XCTAssertEqual(AccountDeletionConfirmationPolicy.confirmationPhrase, "DELETE")
    }

    func testExactPhraseArmsDeletion() {
        XCTAssertTrue(AccountDeletionConfirmationPolicy.isValidConfirmation("DELETE"))
    }

    func testNearMissesDoNotArmDeletion() {
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation("delete"))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation("Delete"))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation("DELET"))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation("DELETEE"))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation("DELETE "))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation(" DELETE"))
        XCTAssertFalse(AccountDeletionConfirmationPolicy.isValidConfirmation(""))
    }

    func testValidationMessageHiddenWhenFieldEmpty() {
        XCTAssertNil(AccountDeletionConfirmationPolicy.validationMessage(for: ""))
    }

    func testValidationMessageHiddenWhenPhraseMatches() {
        XCTAssertNil(AccountDeletionConfirmationPolicy.validationMessage(for: "DELETE"))
    }

    func testValidationMessageShownForNonMatchingInput() {
        XCTAssertEqual(
            AccountDeletionConfirmationPolicy.validationMessage(for: "dele"),
            "Type DELETE exactly to enable account deletion."
        )
    }
}
