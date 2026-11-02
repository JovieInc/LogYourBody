//
//  PersonalBodyEstimate.swift
//  LogYourBody
//
//  On-device front/side outline. The wireframe family is the selected engine.
//  External reconstruction is refused. Shape is not a body-fat measurement.
//

import Foundation

enum PersonalBodyEstimate {
    static let protocolId = "lyb.capture.front-side.v1"
    static let snapshotSchema = "lyb.visualization-snapshot.v1"
    static let modelId = "lyb.wireframe.torso"
    static let modelVersion = "1.0.0"
    static let topologyId = "lyb.wireframe.torso.v1"
    static let rigId = "lyb.wireframe.torso.rig.v1"
    static let maxAttempts = 3
    static let fitBlend = 0.35
    static let dragGain = 0.008
    static let yawLimit = Double.pi
    static let benefitCopy =
        "A front and a side from this session can adjust the personal outline for this date. " +
        "It stays on this phone and does not measure body fat."

    static func defaultShape(frame: Double) -> PersonalBodyShape {
        PersonalBodyShape(adiposity: 0.5, muscularity: 0.5, frame: clampUnit(frame), depth: 0.5)
    }

    static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    static func depthScale(_ depth: Double) -> Double {
        0.85 + clampUnit(depth) * 0.3
    }

    static func fingerprint(_ parts: [String]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    static func sessionKey(_ capture: PersonalBodyCapture) -> String? {
        guard let sessionId = capture.sessionId, capture.view != .diary else { return nil }
        return "\(capture.accountId)|\(sessionId)|\(capture.effectiveDate)"
    }

    static func classifyPose(
        view: PersonalBodyViewKind,
        shoulderSpan: Double?,
        profileDepth: Double?
    ) -> PersonalBodyCaptureQuality {
        if view == .back || view == .diary { return .supported }
        if view == .front {
            guard let shoulderSpan, shoulderSpan.isFinite else { return .missing }
            return shoulderSpan < 0.08 ? .poseChanged : .supported
        }
        guard let profileDepth, profileDepth.isFinite else { return .missing }
        if let shoulderSpan, shoulderSpan > 0.35 { return .poseChanged }
        return .supported
    }

    static func externalProcessing(_ request: PersonalBodyFitRequest) -> String {
        if request.route == .onDevice { return "not-requested" }
        if !request.consentGranted { return "denied" }
        if !request.online || !request.providerAvailable { return "provider-unavailable" }
        return "refused-by-policy"
    }

    static func fitShape(
        captures: [PersonalBodyCapture],
        identity: PersonalBodyIdentity,
        prior: PersonalBodyShape?
    ) -> (shape: PersonalBodyShape, supported: [String], inferred: [String], photoIds: [String], captureIds: [String])? {
        let primary = captures.compactMap(sessionKey).first
        let priorShape = prior ?? defaultShape(frame: identity.frame)
        var widths: [Double] = []
        var depths: [Double] = []
        var photoIds: [String] = []
        var captureIds: [String] = []
        for capture in captures where capture.accountId == identity.accountId && sessionKey(capture) == primary {
            guard let observation = contribution(capture) else { continue }
            captureIds.append(capture.id)
            photoIds.append(capture.photoId)
            if let width = observation.width { widths.append(width) }
            if let depth = observation.depth { depths.append(depth) }
        }
        guard !widths.isEmpty || !depths.isEmpty else { return nil }
        var supported: [String] = []
        var inferred = ["frame", "muscularity"]
        var shape = PersonalBodyShape(
            adiposity: priorShape.adiposity,
            muscularity: priorShape.muscularity,
            frame: clampUnit(identity.frame),
            depth: priorShape.depth
        )
        if widths.isEmpty {
            inferred.append("torsoWidth")
        } else {
            shape.adiposity = blend(priorShape.adiposity, median(widths))
            supported.append("torsoWidth")
        }
        if depths.isEmpty {
            inferred.append("torsoDepth")
        } else {
            shape.depth = blend(priorShape.depth, median(depths))
            supported.append("torsoDepth")
        }
        inferred.append("posterior")
        return (shape, supported, inferred, photoIds, captureIds)
    }

    static func step(existing: PersonalBodyJob?, request: PersonalBodyFitRequest) -> PersonalBodyJobReceipt {
        let id = existing?.id ?? jobIdentifier(request)
        let accountId = request.identity.accountId
        if let existing, existing.status == "settled" {
            let journey = existing.snapshotId == nil ? "photo" : "estimate"
            return PersonalBodyJobReceipt(job: existing, snapshot: nil, diaries: [], journey: journey)
        }
        if let existing, existing.status == "canceled" {
            return PersonalBodyJobReceipt(job: existing, snapshot: nil, diaries: [], journey: "photo")
        }
        let attempts = existing?.attempts ?? 0
        let retryExhausted = existing?.status == "failed" || existing?.status == "timedOut"
        if let existing, retryExhausted, attempts >= maxAttempts {
            return PersonalBodyJobReceipt(job: existing, snapshot: nil, diaries: [], journey: "photo")
        }
        if request.canceled {
            return PersonalBodyJobReceipt(
                job: failed(id, accountId, attempts, "canceled", "canceled"),
                snapshot: nil,
                diaries: diaries(request.captures, request.identity, []),
                journey: "photo"
            )
        }
        if request.now > request.deadline {
            return PersonalBodyJobReceipt(
                job: failed(id, accountId, attempts + 1, "timeout", "timedOut"),
                snapshot: nil,
                diaries: [],
                journey: "photo"
            )
        }
        let boundary = externalProcessing(request)
        if boundary != "not-requested" {
            return PersonalBodyJobReceipt(
                job: failed(id, accountId, attempts + 1, boundary, "failed"),
                snapshot: nil,
                diaries: diaries(request.captures, request.identity, []),
                journey: "photo"
            )
        }
        guard let fitted = fitShape(captures: request.captures, identity: request.identity, prior: request.prior) else {
            return PersonalBodyJobReceipt(
                job: PersonalBodyJob(
                id: id, accountId: accountId, status: "settled", attempts: attempts + 1, snapshotId: nil, failure: nil
            ),
                snapshot: nil,
                diaries: diaries(request.captures, request.identity, []),
                journey: "photo"
            )
        }
        let source = request.captures.first { fitted.captureIds.contains($0.id) }
        let snapshot = makeSnapshot(request, fitted, source)
        return PersonalBodyJobReceipt(
            job: PersonalBodyJob(
                id: id, accountId: accountId, status: "settled", attempts: attempts + 1, snapshotId: snapshot.id, failure: nil
            ),
            snapshot: snapshot,
            diaries: diaries(request.captures, request.identity, fitted.captureIds),
            journey: "estimate"
        )
    }

    static func apply(
        archive: PersonalBodyArchive,
        existing: PersonalBodyJob?,
        request: PersonalBodyFitRequest
    ) -> PersonalBodyArchive {
        let receipt = step(existing: existing, request: request)
        var snapshots = archive.snapshots
        if let snapshot = receipt.snapshot {
            snapshots.removeAll { $0.id == snapshot.id }
            snapshots.append(snapshot)
        }
        var jobs = archive.jobs
        jobs.removeAll { $0.id == receipt.job.id }
        jobs.append(receipt.job)
        return PersonalBodyArchive(
            accountId: archive.accountId,
            captures: mergeCaptures(archive.captures, request.captures),
            diaries: mergeDiaries(archive.diaries, receipt.diaries),
            snapshots: snapshots,
            jobs: jobs
        )
    }

    static func forgetPhoto(_ archive: PersonalBodyArchive, photoId: String) -> PersonalBodyArchive {
        var next = archive
        next.captures.removeAll { $0.photoId == photoId }
        next.diaries.removeAll { $0.photoId == photoId }
        next.snapshots.removeAll { $0.photoIds.contains(photoId) }
        return next
    }

    static func display(for date: String, snapshots: [PersonalBodySnapshot], activeTopology: String) -> PersonalBodyDisplay {
        let unavailable = PersonalBodyDisplay(
            kind: "fallback", shape: nil, topologyId: nil, isolated: false,
            label: "Estimate unavailable for this date", claimsBodyFat: false, claimsWeeklyChange: false
        )
        let exact = snapshots.filter { $0.effectiveDate == date }
        if let chosen = exact.last(where: { $0.topologyId == activeTopology }) {
            return PersonalBodyDisplay(
                kind: "settled", shape: chosen.shape, topologyId: chosen.topologyId, isolated: false,
                label: "Saved date", claimsBodyFat: false, claimsWeeklyChange: false
            )
        }
        if !exact.isEmpty {
            return PersonalBodyDisplay(
                kind: "fallback", shape: nil, topologyId: nil, isolated: true,
                label: "Saved outline uses another model", claimsBodyFat: false, claimsWeeklyChange: false
            )
        }
        let settled = snapshots.filter { $0.topologyId == activeTopology }.sorted { $0.effectiveDate < $1.effectiveDate }
        guard let previous = settled.last(where: { $0.effectiveDate < date }),
              let next = settled.first(where: { $0.effectiveDate > date }),
              previous.shape.frame == next.shape.frame else { return unavailable }
        let span = utcDay(next.effectiveDate) - utcDay(previous.effectiveDate)
        let raw = span > 0 ? Double(utcDay(date) - utcDay(previous.effectiveDate)) / Double(span) : 0
        let t = min(1, max(0, raw))
        return PersonalBodyDisplay(
            kind: "transitional",
            shape: blendShape(previous.shape, next.shape, t),
            topologyId: activeTopology,
            isolated: false,
            label: "Moving between saved dates",
            claimsBodyFat: false,
            claimsWeeklyChange: false
        )
    }

    static func index(dates: [String], snapshots: [PersonalBodySnapshot], topology: String) -> PersonalBodyIndex {
        var displays: [String: PersonalBodyDisplay] = [:]
        for date in dates {
            displays[date] = display(for: date, snapshots: snapshots, activeTopology: topology)
        }
        return PersonalBodyIndex(displays: displays)
    }

    static func morph(left: String, right: String) -> String? {
        left == right ? nil : "cross-topology"
    }

    static func gestureOwner(dx: Double, dy: Double) -> String {
        abs(dx) > abs(dy) ? "timeline" : "rotate"
    }

    static func applyDrag(yaw: Double, dx: Double, dy: Double) -> Double {
        guard gestureOwner(dx: dx, dy: dy) == "rotate" else { return yaw }
        return min(yawLimit, max(-yawLimit, yaw + dy * dragGain))
    }

    static func yaw(for action: String) -> Double {
        action == "side" ? Double.pi / 2 : 0
    }

    static func pairedViewpoints(_ view: PersonalBodyViewpoint) -> (PersonalBodyViewpoint, PersonalBodyViewpoint) {
        (view, view)
    }

    static func jobIdentifier(_ request: PersonalBodyFitRequest) -> String {
        let fitted = fitShape(captures: request.captures, identity: request.identity, prior: request.prior)
        let ids = fitted?.captureIds ?? request.captures.map(\.id)
        let encoded = request.captures.map { capture in
            [
                capture.id, capture.view.rawValue, capture.quality.rawValue, capture.effectiveDate,
                capture.torsoWidth.map { String($0) } ?? "", capture.torsoDepth.map { String($0) } ?? ""
            ].joined(separator: ":")
        }.sorted().joined(separator: "|")
        return fingerprint([
            request.identity.accountId, request.identity.bodyId, request.activeTopology, request.route.rawValue,
            request.prior.map { String($0.adiposity) } ?? "", request.prior.map { String($0.depth) } ?? "",
            ids.sorted().joined(separator: ","), encoded
        ])
    }

    private static func contribution(_ capture: PersonalBodyCapture) -> (width: Double?, depth: Double?)? {
        guard sessionKey(capture) != nil, capture.quality == .supported else { return nil }
        if capture.view == .front, let width = unit(capture.torsoWidth) { return (width, nil) }
        if capture.view == .side, let depth = unit(capture.torsoDepth) { return (nil, depth) }
        return nil
    }

    private static func unit(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    private static func blend(_ prior: Double, _ observed: Double) -> Double {
        clampUnit(prior + (observed - prior) * fitBlend)
    }

    private static func blendShape(_ start: PersonalBodyShape, _ end: PersonalBodyShape, _ t: Double) -> PersonalBodyShape {
        PersonalBodyShape(
            adiposity: start.adiposity + (end.adiposity - start.adiposity) * t,
            muscularity: start.muscularity + (end.muscularity - start.muscularity) * t,
            frame: start.frame,
            depth: start.depth + (end.depth - start.depth) * t
        )
    }

    private static func failed(
        _ id: String,
        _ accountId: String,
        _ attempts: Int,
        _ failure: String?,
        _ status: String
    ) -> PersonalBodyJob {
        PersonalBodyJob(id: id, accountId: accountId, status: status, attempts: attempts, snapshotId: nil, failure: failure)
    }

    private static func diaries(
        _ captures: [PersonalBodyCapture],
        _ identity: PersonalBodyIdentity,
        _ used: [String]
    ) -> [PersonalBodyDiary] {
        captures.compactMap { capture in
            guard capture.accountId == identity.accountId, !used.contains(capture.id) else { return nil }
            let casual = capture.view == .diary || capture.sessionId == nil
            return PersonalBodyDiary(
                accountId: capture.accountId,
                photoId: capture.photoId,
                effectiveDate: capture.effectiveDate,
                reason: casual ? "casual" : "unsupported"
            )
        }
    }

    private static func makeSnapshot(
        _ request: PersonalBodyFitRequest,
        _ fitted: (shape: PersonalBodyShape, supported: [String], inferred: [String], photoIds: [String], captureIds: [String]),
        _ source: PersonalBodyCapture?
    ) -> PersonalBodySnapshot {
        let shape = fitted.shape
        let id = fingerprint([
            snapshotSchema, request.identity.accountId, request.identity.bodyId, source?.effectiveDate ?? "",
            source?.sessionId ?? "", modelVersion, request.activeTopology,
            String(format: "%.5f", shape.adiposity), String(format: "%.5f", shape.muscularity),
            String(format: "%.5f", shape.frame), String(format: "%.5f", shape.depth),
            fitted.captureIds.sorted().joined(separator: ",")
        ])
        return PersonalBodySnapshot(
            schema: snapshotSchema, id: id, accountId: request.identity.accountId, bodyId: request.identity.bodyId,
            frame: shape.frame, modelId: modelId, modelVersion: modelVersion, topologyId: request.activeTopology,
            rigId: rigId, effectiveDate: source?.effectiveDate ?? "", sessionId: source?.sessionId, shape: shape,
            supported: fitted.supported, inferred: fitted.inferred, evidence: "settled", photoIds: fitted.photoIds,
            captureIds: fitted.captureIds, claimsBodyFat: false, claimsWeeklyChange: false
        )
    }

    private static func mergeCaptures(_ current: [PersonalBodyCapture], _ added: [PersonalBodyCapture]) -> [PersonalBodyCapture] {
        var next = current
        for capture in added {
            if let index = next.firstIndex(where: { $0.id == capture.id && $0.accountId == capture.accountId }) {
                next[index] = capture
            } else {
                next.append(capture)
            }
        }
        return next
    }

    private static func mergeDiaries(_ current: [PersonalBodyDiary], _ added: [PersonalBodyDiary]) -> [PersonalBodyDiary] {
        var next = current
        for entry in added where !next.contains(where: {
            $0.accountId == entry.accountId && $0.photoId == entry.photoId && $0.effectiveDate == entry.effectiveDate
        }) {
            next.append(entry)
        }
        return next
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func utcDay(_ day: String) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return 0
        }
        return Int(date.timeIntervalSince1970 / 86_400)
    }
}

enum PersonalBodyPolicy {
    static let killSwitchKey = "personal_body_estimate_kill_switch"
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: "personal_body_estimate",
        killSwitchKey: killSwitchKey,
        stage: .graduated,
        minimumBuild: nil
    )

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return FeatureReleaseEvaluator.evaluate(
            releaseDescriptor,
            context: FeatureReleaseContext(
                actor: .ordinaryCustomer,
                installedBuild: 1,
                configState: .fresh,
                enableGate: false,
                killSwitch: check(killSwitchKey)
            )
        ).isEnabled
    }
}
