//
//  PersonalBodyEstimateStore.swift
//  LogYourBody
//
//  Account-scoped outline snapshots. File work stays off the main actor.
//  Deleting the account or a source photo deletes the derived outline.
//

import Foundation

actor PersonalBodyEstimateStore {
    static let shared = PersonalBodyEstimateStore()

    private let root: URL?
    private var memory: [String: PersonalBodyArchive] = [:]

    init(root: URL? = nil) {
        self.root = root
    }

    func index(accountId: String, dates: [String]) -> PersonalBodyIndex {
        let archive = load(accountId)
        return PersonalBodyEstimate.index(
            dates: dates,
            snapshots: archive.snapshots.filter { $0.accountId == accountId },
            topology: PersonalBodyEstimate.topologyId
        )
    }

    func record(
        _ capture: PersonalBodyCapture,
        identity: PersonalBodyIdentity,
        now: Int,
        deadline: Int,
        route: PersonalBodyRoute = .onDevice,
        consentGranted: Bool = false,
        providerAvailable: Bool = false,
        canceled: Bool = false,
        online: Bool = true
    ) -> PersonalBodyJobReceipt {
        var archive = load(identity.accountId)
        archive.captures = merged(archive.captures, capture)
        let session = archive.captures.filter {
            $0.accountId == identity.accountId &&
                $0.sessionId == capture.sessionId &&
                $0.effectiveDate == capture.effectiveDate
        }
        let prior = archive.snapshots
            .filter { $0.accountId == identity.accountId && $0.effectiveDate < capture.effectiveDate }
            .filter { $0.topologyId == PersonalBodyEstimate.topologyId }
            .max { $0.effectiveDate < $1.effectiveDate }?
            .shape
        let request = PersonalBodyFitRequest(
            now: now,
            deadline: deadline,
            online: online,
            route: route,
            consentGranted: consentGranted,
            providerAvailable: providerAvailable,
            canceled: canceled,
            identity: identity,
            captures: session.isEmpty ? [capture] : session,
            prior: prior,
            activeTopology: PersonalBodyEstimate.topologyId
        )
        let existing = archive.jobs.first { $0.id == PersonalBodyEstimate.jobIdentifier(request) }
        let receipt = PersonalBodyEstimate.step(existing: existing, request: request)
        archive = PersonalBodyEstimate.apply(archive: archive, existing: existing, request: request)
        memory[identity.accountId] = archive
        persist(archive)
        return receipt
    }

    func forget(accountId: String, photoId: String) {
        let next = PersonalBodyEstimate.forgetPhoto(load(accountId), photoId: photoId)
        memory[accountId] = next
        persist(next)
    }

    func forgetAccount(_ accountId: String) {
        let empty = PersonalBodyArchive.empty(accountId)
        memory[accountId] = empty
        persist(empty)
        if let url = fileURL(accountId) {
            try? FileManager.default.removeItem(at: url)
        }
        memory[accountId] = empty
    }

    private func load(_ accountId: String) -> PersonalBodyArchive {
        if let stored = memory[accountId] { return stored }
        guard let url = fileURL(accountId),
              let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(PersonalBodyArchive.self, from: data),
              archive.accountId == accountId else {
            return PersonalBodyArchive.empty(accountId)
        }
        memory[accountId] = archive
        return archive
    }

    private func persist(_ archive: PersonalBodyArchive) {
        guard let url = fileURL(archive.accountId),
              let data = try? JSONEncoder().encode(archive) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func merged(_ current: [PersonalBodyCapture], _ capture: PersonalBodyCapture) -> [PersonalBodyCapture] {
        var next = current
        if let index = next.firstIndex(where: { $0.id == capture.id && $0.accountId == capture.accountId }) {
            next[index] = capture
        } else {
            next.append(capture)
        }
        return next
    }

    private func fileURL(_ accountId: String) -> URL? {
        let name = accountId.map { $0.isLetter || $0.isNumber ? $0 : "-" } + ".json"
        if let root { return root.appendingPathComponent(String(name)) }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("personal-body", isDirectory: true)
            .appendingPathComponent(String(name))
    }
}
