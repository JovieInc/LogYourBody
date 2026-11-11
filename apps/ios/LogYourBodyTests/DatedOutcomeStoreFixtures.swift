import CoreData
import XCTest
@testable import LogYourBody

final class FailingOutcomeContext: NSManagedObjectContext {
    var failSave = false
    override func save() throws {
        if failSave { throw DatedOutcomeError.unavailable }
        try super.save()
    }
}

@MainActor
final class OutcomeRemoteFixture: DatedOutcomeRemote {
    var requests: [DatedOutcomeEdit] = []
    var latest: DatedOutcomeSnapshot?
    var failNextSave = false
    var conflicts = false
    var onSave: (() -> Void)?
    var reads = 0

    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot {
        requests.append(edit)
        onSave?()
        if conflicts { throw ProductAPIError.httpError(409) }
        if failNextSave { failNextSave = false; throw DatedOutcomeError.unavailable }
        let receipt = DatedOutcomeSnapshot(revision: edit.requestId, value: edit.value)
        latest = receipt
        return receipt
    }

    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot? {
        reads += 1
        return latest
    }
}
