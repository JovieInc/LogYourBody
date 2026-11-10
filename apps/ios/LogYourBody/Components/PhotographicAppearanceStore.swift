//
//  PhotographicAppearanceStore.swift
//  LogYourBody
//
//  Cached photo projection for one account. A date scrub reads this cache.
//  Deleting the account or a source photo deletes the derived texture.
//

import Foundation

actor PhotographicAppearanceStore {
    static let shared = PhotographicAppearanceStore()

    private let root: URL?
    private var memory: [String: PhotographicAppearanceArchive] = [:]

    init(root: URL? = nil) {
        self.root = root
    }

    func index(accountId: String, dates: [String]) -> [String: PhotographicAppearanceDisplay] {
        let assets = load(accountId).assets.filter { $0.accountId == accountId }
        var displays: [String: PhotographicAppearanceDisplay] = [:]
        for date in dates {
            guard let asset = PhotographicAppearance.lookup(
                date: date,
                cache: assets,
                topologyId: PhotographicAppearance.topologyId
            ) else { continue }
            displays[date] = PhotographicAppearance.display(for: asset)
        }
        return displays
    }

    func remember(
        _ sample: PhotographicAppearanceSample,
        geometry: PhotographicAppearanceGeometry,
        options: PhotographicAppearanceOptions = .precompute
    ) -> PhotographicAppearanceResult {
        let archive = PhotographicAppearance.remember(
            archive: load(geometry.accountId),
            sample: sample,
            geometry: geometry,
            options: options
        )
        memory[geometry.accountId] = archive
        persist(archive)
        let dated = archive.samples.filter {
            $0.accountId == geometry.accountId && $0.effectiveDate == geometry.effectiveDate
        }
        return PhotographicAppearance.project(geometry: geometry, samples: dated, options: options)
    }

    func forget(accountId: String, photoId: String) {
        let next = PhotographicAppearance.forgetPhoto(load(accountId), photoId: photoId)
        memory[accountId] = next
        persist(next)
    }

    func forgetAccount(_ accountId: String) {
        let empty = PhotographicAppearanceArchive.empty(accountId)
        memory[accountId] = empty
        persist(empty)
        if let url = fileURL(accountId) {
            try? FileManager.default.removeItem(at: url)
        }
        memory[accountId] = empty
    }

    private func load(_ accountId: String) -> PhotographicAppearanceArchive {
        if let stored = memory[accountId] { return stored }
        guard let url = fileURL(accountId),
              let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(PhotographicAppearanceArchive.self, from: data),
              archive.accountId == accountId else {
            return PhotographicAppearanceArchive.empty(accountId)
        }
        memory[accountId] = archive
        return archive
    }

    private func persist(_ archive: PhotographicAppearanceArchive) {
        guard let url = fileURL(archive.accountId),
              let data = try? JSONEncoder().encode(archive) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(_ accountId: String) -> URL? {
        let name = accountId.map { $0.isLetter || $0.isNumber ? $0 : "-" } + ".json"
        if let root { return root.appendingPathComponent(String(name)) }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("photographic-appearance", isDirectory: true)
            .appendingPathComponent(String(name))
    }
}
