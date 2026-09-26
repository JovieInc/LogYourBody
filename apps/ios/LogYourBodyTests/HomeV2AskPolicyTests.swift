//
// HomeV2AskPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2AskPolicyTests: XCTestCase {
    func testAReplyWithoutAProofIsAllBody() {
        let reply = HomeV2AskReply.split("Nine weeks so far, losing 0.6% a week.\n\nCuts past 12 weeks tend to stall.")
        XCTAssertEqual(reply.body, "Nine weeks so far, losing 0.6% a week.\n\nCuts past 12 weeks tend to stall.")
        XCTAssertNil(reply.proof)
    }

    func testAProofParagraphSplitsOffAndKeepsItsWords() {
        let text = "Nine weeks so far.\n\nProof: Weight is measured, from Apple Health. Body fat is estimated."
        let reply = HomeV2AskReply.split(text)
        XCTAssertEqual(reply.body, "Nine weeks so far.")
        XCTAssertEqual(reply.proof, "Weight is measured, from Apple Health. Body fat is estimated.")

        let headed = HomeV2AskReply.split("Body.\n\nproof\n\nWeight is measured.\n\nLean mass is estimated.")
        XCTAssertEqual(headed.body, "Body.")
        XCTAssertEqual(headed.proof, "Weight is measured.\n\nLean mass is estimated.")
    }

    func testAnEmptyProofDoesNotCount() {
        let reply = HomeV2AskReply.split("Body.\n\nProof:")
        XCTAssertEqual(reply.body, "Body.")
        XCTAssertNil(reply.proof)
    }
}
