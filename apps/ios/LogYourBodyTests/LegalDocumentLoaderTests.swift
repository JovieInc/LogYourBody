import XCTest
@testable import LogYourBody

final class LegalDocumentLoaderTests: XCTestCase {
    private typealias DocumentType = LegalDocumentView.LegalDocumentType

    func testEveryAdvertisedDocumentShipsNonEmptyInAppBundle() {
        for documentType in DocumentType.allCases {
            let content = LegalDocumentLoader.loadMarkdown(for: documentType, in: .main)
            XCTAssertFalse(
                content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(documentType.filename) must ship non-empty markdown"
            )
            XCTAssertFalse(
                content.contains("couldn't load"),
                "\(documentType.filename) served the embedded fallback; the real document is missing from the app bundle"
            )
        }
    }

    func testEachDocumentTypeMapsToDistinctContent() {
        var seen: Set<String> = []
        for documentType in DocumentType.allCases {
            let content = LegalDocumentLoader.loadMarkdown(for: documentType, in: .main)
            XCTAssertTrue(
                seen.insert(content).inserted,
                "\(documentType) serves the same content as another document"
            )
        }
        XCTAssertEqual(seen.count, DocumentType.allCases.count)
    }

    func testFallbackServesEmbeddedCopyWhenBundleLacksDocument() {
        let bundleWithoutLegalDocs = Bundle(for: BundleToken.self)
        for documentType in DocumentType.allCases {
            let content = LegalDocumentLoader.loadMarkdown(for: documentType, in: bundleWithoutLegalDocs)
            XCTAssertTrue(
                content.contains("couldn't load"),
                "\(documentType) fallback should explain the document could not load"
            )
            XCTAssertTrue(
                content.contains(documentType.title),
                "\(documentType) fallback should keep the document title"
            )
            XCTAssertTrue(
                content.contains(ProductRegistry.supportEmail),
                "\(documentType) fallback should point at support"
            )
        }
    }
}

private final class BundleToken { }
