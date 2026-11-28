//
// InteractionSignpost.swift
// LogYourBody
//
// Fixed Instruments names for work that must leave the interaction path.
// Messages stay empty so health values never enter the log.
//

import Foundation
import os

enum InteractionSignpost {
    static let exportEncode = "export_encode"
    static let purchaseAdmit = "purchase_admit"
    static let registered = [exportEncode, purchaseAdmit]

    private static let log = OSLog(subsystem: "com.logyourbody.app", category: "InteractionPath")
    private static let sink = InteractionSignpostSink()

    /// Test seam. Production events record only a registered name.
    static var testLines: (@Sendable (String) -> Void)? {
        get { sink.reader }
        set { sink.reader = newValue }
    }

    static func emitPurchaseAdmit() {
        record(purchaseAdmit)
        os_signpost(.event, log: log, name: "purchase_admit")
    }

    static func measureExportEncode<T>(_ work: () throws -> T) rethrows -> T {
        record(exportEncode)
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "export_encode", signpostID: id)
        defer { os_signpost(.end, log: log, name: "export_encode", signpostID: id) }
        return try work()
    }

    private static func record(_ name: String) {
        sink.record(name)
    }
}

private final class InteractionSignpostSink: @unchecked Sendable {
    private let lock = NSLock()
    var reader: (@Sendable (String) -> Void)?

    func record(_ name: String) {
        lock.lock()
        let reader = reader
        lock.unlock()
        reader?(name)
    }
}
