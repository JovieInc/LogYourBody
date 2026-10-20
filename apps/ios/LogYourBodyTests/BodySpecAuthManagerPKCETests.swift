//
// BodySpecAuthManagerPKCETests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Covers the deterministic PKCE surface of `BodySpecAuthManager` (RFC 7636).
/// The OAuth web session itself (`ASWebAuthenticationSession`) cannot be faked,
/// so these tests exercise the pure crypto helpers directly.
@MainActor
final class BodySpecAuthManagerPKCETests: XCTestCase {
    private let allowedVerifierCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    func testCodeVerifierHasRFC7636LengthOf64() {
        let manager = BodySpecAuthManager()

        for _ in 0..<10 {
            XCTAssertEqual(manager.generateCodeVerifier().count, 64)
        }
    }

    func testCodeVerifierUsesOnlyRFC7636UnreservedCharacters() {
        let manager = BodySpecAuthManager()

        for _ in 0..<10 {
            let verifier = manager.generateCodeVerifier()
            XCTAssertTrue(
                verifier.allSatisfy(allowedVerifierCharacters.contains),
                "Verifier contained characters outside the RFC 7636 unreserved set: \(verifier)"
            )
        }
    }

    func testCodeVerifierIsUniqueAcrossCalls() {
        let manager = BodySpecAuthManager()

        let verifiers = (0..<200).map { _ in manager.generateCodeVerifier() }

        XCTAssertEqual(Set(verifiers).count, verifiers.count)
    }

    func testCodeChallengeMatchesRFC7636AppendixBVector() {
        let manager = BodySpecAuthManager()

        let challenge = manager.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testCodeChallengeAppliesBase64URLReplacementsAndStripsPadding() {
        // Fixed vector whose plain base64 digest contains '+', '/', and '='
        // padding, so every replacement branch is exercised deterministically.
        let manager = BodySpecAuthManager()

        let challenge = manager.codeChallenge(for: "bodyspec-pkce-vector-0")

        XCTAssertEqual(challenge, "WUoBy_PYgnjGsT8YZB-3Zbaw9EALd1kC1_AuXImUvMo")
        XCTAssertEqual(challenge.count, 43)
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testCodeChallengeIsDeterministicForSameVerifier() {
        let manager = BodySpecAuthManager()
        let verifier = "deterministic-verifier-123"

        XCTAssertEqual(manager.codeChallenge(for: verifier), manager.codeChallenge(for: verifier))
    }
}
