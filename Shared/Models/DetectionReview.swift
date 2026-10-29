import Foundation
import CryptoKit

/// Where an automatic smoking detection was observed.
public enum DetectionReviewOrigin: String, Codable, Equatable, Sendable {
	case liveWatch
	case watchHistory
}

/// A summary remains passive until the user chooses to review its count.
public enum DetectionReviewDecision: String, Codable, Equatable, Sendable {
	case pending
	case accurate
	case adjusted
}

/// A single user decision, independent of WatchConnectivity delivery order.
public struct DetectionCorrection: Codable, Equatable, Sendable {
    public let operationID: UUID
    /// Numeric reference time survives legacy ISO-8601 transports without truncation.
    public let decidedAtReferenceTime: Double

    public init(operationID: UUID = UUID(), decidedAt: Date = Date()) {
        self.operationID = operationID
        self.decidedAtReferenceTime = decidedAt.timeIntervalSinceReferenceDate
    }
}

/// A synchronized, non-blocking review of one or more automatically logged events.
public struct DetectionReview: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public var eventIDs: [UUID]
	public var origin: DetectionReviewOrigin
	public var windowStart: Date
	public var windowEnd: Date
	public var decision: DetectionReviewDecision
	public var correctedCount: Int?
	public var reviewedAt: Date?
	public var updatedAt: Date
	/// Monotonic merge key used when WatchConnectivity delivers updates at least once.
	public var revision: Int
	/// Calendar day covered by a new summary. Legacy summaries did not store a day.
	public var dayStart: Date?
	/// Identifies a legacy summary replaced by deterministic day-scoped summaries.
	public var parentReviewID: UUID?
    /// Original records travel with the review so a correction can precede event delivery.
    public var eventSnapshots: [SmokingEvent]
    /// Absent on legacy reviews, whose individual event mutations must not be replayed.
    public var correction: DetectionCorrection?
    public var continuationOf: UUID?

    private enum CodingKeys: String, CodingKey {
        case id, eventIDs, origin, windowStart, windowEnd, decision, correctedCount, reviewedAt, updatedAt
        case revision, dayStart, parentReviewID, eventSnapshots, correction, continuationOf
        case windowStartReferenceTime, windowEndReferenceTime, reviewedAtReferenceTime, updatedAtReferenceTime, dayStartReferenceTime
    }

	public init(
		id: UUID = UUID(),
		eventIDs: [UUID],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		decision: DetectionReviewDecision = .pending,
		correctedCount: Int? = nil,
		reviewedAt: Date? = nil,
		updatedAt: Date = Date(),
		revision: Int = 1,
		dayStart: Date? = nil,
		parentReviewID: UUID? = nil,
        eventSnapshots: [SmokingEvent] = [],
        correction: DetectionCorrection? = nil,
        continuationOf: UUID? = nil
	) {
		self.id = id
		self.eventIDs = Self.unique(eventIDs)
		self.origin = origin
		self.windowStart = min(windowStart, windowEnd)
		self.windowEnd = max(windowStart, windowEnd)
		self.decision = decision
		self.correctedCount = correctedCount.map { max(0, min(100, $0)) }
		self.reviewedAt = reviewedAt
		self.updatedAt = updatedAt
		self.revision = max(1, revision)
		self.dayStart = dayStart
		self.parentReviewID = parentReviewID
        self.eventSnapshots = eventSnapshots
        self.correction = correction
        self.continuationOf = continuationOf
	}

	public var originalCount: Int { eventIDs.count }
	public var displayCount: Int { correctedCount ?? originalCount }

    /// Log timestamps describe the detections, not scan coverage or delivery time.
    /// Require every original: a partially delivered legacy review cannot claim
    /// that the available subset describes the whole count.
    public var estimatedLogRange: ClosedRange<Date>? {
        guard eventIDs.isEmpty == false else { return nil }
        let snapshots = Dictionary(eventSnapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dates = eventIDs.compactMap { snapshots[$0]?.timestamp }
        guard dates.count == eventIDs.count, dates.allSatisfy(MotionHistoryProcessor.isSupportedDate),
              let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    public func timingSummary(now: Date = Date(), calendar: Calendar = .current,
                              locale: Locale = .autoupdatingCurrent) -> String {
        let logs = estimatedLogRange
        let start = logs?.lowerBound ?? windowStart
        let end = logs?.upperBound ?? windowEnd
        let label = logs == nil ? "Review period" : (decision == .adjusted ? "Original estimates" : "Estimated logs")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        let startTime = formatter.string(from: start)
        let endTime = formatter.string(from: end)
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.timeStyle = .none
            formatter.dateStyle = .medium
            let day = calendar.isDate(end, inSameDayAs: now) ? "Today" : formatter.string(from: end)
            let times = startTime == endTime ? endTime : "\(startTime) – \(endTime)"
            return "\(label): \(day) · \(times)"
        }
        formatter.dateStyle = .medium
        return "\(label): \(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

	public var historyHours: Int {
		let hours = ceil(windowEnd.timeIntervalSince(windowStart) / 3_600)
		guard hours.isFinite, hours > 0 else { return 1 }
		// A malformed persisted date must never trap during a Double-to-Int conversion.
		return Int(min(hours, Double(Int.max / 2)))
	}

	var hasValidDates: Bool {
		[windowStart, windowEnd, updatedAt].allSatisfy {
			$0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
		} && [reviewedAt, dayStart].compactMap { $0 }.allSatisfy {
			$0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
		} && (correction.map {
            let date = Date(timeIntervalSinceReferenceDate: $0.decidedAtReferenceTime)
            return decision != .pending && date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
        } ?? true) && eventSnapshots.allSatisfy { event in
            [event.timestamp, event.motionSessionStartedAt].compactMap { $0 }.allSatisfy {
                $0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
            }
        } && (correction == nil || (decision == .accurate ? correctedCount == nil :
            correctedCount.map { (0...100).contains($0) } == true))
	}

	/// Decode through the initializer so received and saved reviews have the same invariants.
	public init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
        func date(_ key: CodingKeys, _ exact: CodingKeys) throws -> Date {
            if let time = try values.decodeIfPresent(Double.self, forKey: exact) { return Date(timeIntervalSinceReferenceDate: time) }
            return try values.decode(Date.self, forKey: key)
        }
        func optionalDate(_ key: CodingKeys, _ exact: CodingKeys) throws -> Date? {
            if let time = try values.decodeIfPresent(Double.self, forKey: exact) { return Date(timeIntervalSinceReferenceDate: time) }
            return try values.decodeIfPresent(Date.self, forKey: key)
        }
		self.init(
			id: try values.decode(UUID.self, forKey: .id),
			eventIDs: try values.decode([UUID].self, forKey: .eventIDs),
			origin: try values.decode(DetectionReviewOrigin.self, forKey: .origin),
			windowStart: try date(.windowStart, .windowStartReferenceTime),
			windowEnd: try date(.windowEnd, .windowEndReferenceTime),
			decision: try values.decode(DetectionReviewDecision.self, forKey: .decision),
			correctedCount: try values.decodeIfPresent(Int.self, forKey: .correctedCount),
			reviewedAt: try optionalDate(.reviewedAt, .reviewedAtReferenceTime),
			updatedAt: try date(.updatedAt, .updatedAtReferenceTime),
			revision: try values.decode(Int.self, forKey: .revision),
			dayStart: try optionalDate(.dayStart, .dayStartReferenceTime),
			parentReviewID: try values.decodeIfPresent(UUID.self, forKey: .parentReviewID),
            eventSnapshots: try values.decodeIfPresent([SmokingEvent].self, forKey: .eventSnapshots) ?? [],
            correction: try values.decodeIfPresent(DetectionCorrection.self, forKey: .correction),
            continuationOf: try values.decodeIfPresent(UUID.self, forKey: .continuationOf)
		)
	}

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(eventIDs, forKey: .eventIDs)
        try values.encode(origin, forKey: .origin)
        try values.encode(windowStart, forKey: .windowStart)
        try values.encode(windowEnd, forKey: .windowEnd)
        try values.encode(decision, forKey: .decision)
        try values.encodeIfPresent(correctedCount, forKey: .correctedCount)
        try values.encodeIfPresent(reviewedAt, forKey: .reviewedAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(revision, forKey: .revision)
        try values.encodeIfPresent(dayStart, forKey: .dayStart)
        try values.encodeIfPresent(parentReviewID, forKey: .parentReviewID)
        try values.encode(eventSnapshots, forKey: .eventSnapshots)
        try values.encodeIfPresent(correction, forKey: .correction)
        try values.encodeIfPresent(continuationOf, forKey: .continuationOf)
        try values.encode(windowStart.timeIntervalSinceReferenceDate, forKey: .windowStartReferenceTime)
        try values.encode(windowEnd.timeIntervalSinceReferenceDate, forKey: .windowEndReferenceTime)
        try values.encodeIfPresent(reviewedAt?.timeIntervalSinceReferenceDate, forKey: .reviewedAtReferenceTime)
        try values.encode(updatedAt.timeIntervalSinceReferenceDate, forKey: .updatedAtReferenceTime)
        try values.encodeIfPresent(dayStart?.timeIntervalSinceReferenceDate, forKey: .dayStartReferenceTime)
    }

    /// A total order: replay and simultaneous offline decisions choose the same winner.
    func isPreferred(to other: DetectionReview) -> Bool {
        if (correction != nil) != (other.correction != nil) { return correction != nil }
        if revision != other.revision { return revision > other.revision }
        let time = correction?.decidedAtReferenceTime ?? updatedAt.timeIntervalSinceReferenceDate
        let otherTime = other.correction?.decidedAtReferenceTime ?? other.updatedAt.timeIntervalSinceReferenceDate
        if time != otherTime { return time > otherTime }
        let operation = correction?.operationID.uuidString ?? ""
        let otherOperation = other.correction?.operationID.uuidString ?? ""
        if operation != otherOperation { return operation > otherOperation }
        return decisionKey > other.decisionKey
    }

    private var decisionKey: String {
        // Exclude mergeable original snapshots; their arrival cannot change a decision's rank.
        [decision.rawValue, String(correctedCount ?? -1), eventIDs.map(\.uuidString).joined(separator: ":"),
         String(windowStart.timeIntervalSinceReferenceDate), String(windowEnd.timeIntervalSinceReferenceDate),
         origin.rawValue, String(updatedAt.timeIntervalSinceReferenceDate),
         reviewedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
         dayStart.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
         parentReviewID?.uuidString ?? "", continuationOf?.uuidString ?? ""].joined(separator: "|")
    }

    static func stableID(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// A later parent decision can cover detections that previously lived in a
    /// continuation. Keep canonical decisions immutable, but project each scope
    /// so no event (or fully superseded correction's additions) is counted twice.
    static func effectiveScopes(_ reviews: [DetectionReview], resolvingEventID: (UUID) -> UUID = { $0 }) -> [DetectionReview] {
        let byID = Dictionary(reviews.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inferredParents = Dictionary(reviews.map {
            (stableID("ciggy-review-continuation-v1:\($0.id.uuidString)"), $0.id)
        }, uniquingKeysWith: { first, _ in first })
        func ancestors(of review: DetectionReview) -> [DetectionReview] {
            var parent = review.continuationOf ?? inferredParents[review.id]
            var visited: Set<UUID> = [review.id]
            var result: [DetectionReview] = []
            while let id = parent, visited.insert(id).inserted, let ancestor = byID[id] {
                result.append(ancestor)
                parent = ancestor.continuationOf ?? inferredParents[id]
            }
            return result
        }
        let ancestorLists = Dictionary(reviews.map { ($0.id, ancestors(of: $0)) }, uniquingKeysWith: { first, _ in first })
        return reviews.compactMap { saved in
            var original = saved
            var seen = Set<UUID>()
            original.eventIDs = saved.eventIDs.filter { seen.insert(resolvingEventID($0)).inserted }
            var claimed = Set((ancestorLists[original.id] ?? []).flatMap(\.eventIDs).map(resolvingEventID))
            for other in reviews where other.id != original.id && other.correction != nil && other.decision != .pending {
                // A continuation cannot take scope back from its own parent.
                guard (ancestorLists[other.id] ?? []).contains(where: { $0.id == original.id }) == false else { continue }
                let preferred = other.isPreferred(to: original) ||
                    (!original.isPreferred(to: other) && other.id.uuidString > original.id.uuidString)
                if original.decision == .pending || preferred {
                    claimed.formUnion(other.eventIDs.map(resolvingEventID))
                }
            }
            let remaining = original.eventIDs.filter { claimed.contains(resolvingEventID($0)) == false }
            guard remaining.isEmpty == false || original.eventIDs.isEmpty else { return nil }
            var effective = original
            if original.decision == .adjusted, remaining != original.eventIDs {
                let kept = original.eventIDs.prefix(original.displayCount).filter { claimed.contains(resolvingEventID($0)) == false }.count
                let added = max(0, original.displayCount - original.originalCount)
                effective.correctedCount = kept + added
            }
            effective.eventIDs = remaining
            effective.eventSnapshots = original.eventSnapshots.filter { remaining.contains($0.id) }
            return effective
        }
    }

    /// Stable slots let a winning lower count remove additions from a losing higher count.
    public func correctionEventID(at index: Int) -> UUID {
        Self.stableID("ciggy-review-added-v1:\(id.uuidString):\(index)")
    }

	private static func unique(_ ids: [UUID]) -> [UUID] {
		var seen = Set<UUID>()
		return ids.filter { seen.insert($0).inserted }
	}
}
