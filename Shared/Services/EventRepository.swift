import Foundation
import Combine

/// Atomically persisted original events, explicit deletions, and derived correction effects.
/// Existing UserDefaults snapshots migrate without changing accepted event identities.
@MainActor
public final class EventRepository: ObservableObject {
	@Published public private(set) var events: [SmokingEvent] = []

	@Published public private(set) var lastPersistenceError: String?
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let deletedStorageKey: String
    private let snapshotFile: DurableSnapshotFile?
    private let snapshotWriter: ((Data) throws -> Void)?
    private var loadFailed = false
    private var rawEvents: [SmokingEvent] = []
    private var deletedEventIDs: Set<UUID> = []
    private var automaticEventTimes: [UUID: Date] = [:]
    private var automaticSessionStarts: [UUID: Date] = [:]
    private var correctionReviews: [DetectionReview] = []
    private var eventAliases: [UUID: UUID] = [:]
    private struct EventMutation: Codable, Equatable {
        let id: UUID
        let event: SmokingEvent?
        let deletedID: UUID?
    }
    private var pendingEventMutations: [EventMutation] = []
    public var pendingEventMutationCount: Int { pendingEventMutations.count }
    private var enqueueEvent: ((SmokingEvent) -> Bool)?
    private var enqueueDeletion: ((UUID) -> Bool)?
    private var isSendingEventMutations = false
    private var automaticTimesKey: String { "\(storageKey).automaticTimes.v1" }
    private struct Snapshot: Codable, Equatable {
        var events: [SmokingEvent]
        var deletedEventIDs: Set<UUID>
        var automaticEventTimes: [UUID: Date]
        var automaticSessionStarts: [UUID: Date]?
        var correctionReviews: [DetectionReview]?
        var eventAliases: [UUID: UUID]?
        var pendingEventMutations: [EventMutation]?
    }

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "EventRepository.events.v1",
        snapshotURL: URL? = nil,
        snapshotWriter: ((Data) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.deletedStorageKey = "\(storageKey).deleted.v1"
        self.snapshotFile = (snapshotURL ?? (userDefaults === UserDefaults.standard ?
            DurableSnapshotFile.defaultURL(name: storageKey) : nil)).map { DurableSnapshotFile(url: $0) }
        self.snapshotWriter = snapshotWriter
        load()
    }

    @discardableResult
    public func addEvent(_ event: SmokingEvent) -> Bool {
        addEvent(event, journalDelivery: true)
    }

    private func addEvent(_ event: SmokingEvent, journalDelivery: Bool) -> Bool {
        guard let event = Self.validated(event) else { return false }
        var next = snapshot
        if event.source == .automatic {
            let matchedID = automaticSessionID(matching: event)
            let retainedID = matchedID ?? event.id
            if let matchedID, matchedID != event.id { next.eventAliases?[event.id] = matchedID }
            let start = event.motionSessionStartedAt ?? event.timestamp
            next.automaticSessionStarts?[retainedID] = min(automaticSessionStarts[retainedID] ?? automaticEventTimes[retainedID] ?? start, start)
            next.automaticEventTimes[retainedID] = max(automaticEventTimes[retainedID] ?? event.timestamp, event.timestamp)
            if matchedID != nil || deletedEventIDs.contains(event.id) {
                if next != snapshot { _ = commit(next) }
                return false
            }
        }
        guard deletedEventIDs.contains(event.id) == false,
              rawEvents.contains(where: { $0.id == event.id }) == false else {
            lastPersistenceError = loadFailed ? lastPersistenceError : nil
            return false
        }
        next.events.append(event)
        next.events.sort(by: Self.eventOrder)
        if journalDelivery { next.pendingEventMutations?.append(.init(id: UUID(), event: event, deletedID: nil)) }
        guard commit(next) else { return false }
        let added = events.contains { $0.id == event.id }
        if journalDelivery, enqueueEvent != nil { _ = retryPendingEventMutations() }
        return added
    }

    /// Transport receipt is independent of whether an idempotent mutation changed the UI.
    public func receiveEvent(_ event: SmokingEvent) -> Bool {
        guard loadFailed == false, Self.validated(event) != nil else { return false }
        lastPersistenceError = nil
        _ = addEvent(event, journalDelivery: false)
        return lastPersistenceError == nil
    }

    public func receiveDeletion(id: UUID) -> Bool {
        guard loadFailed == false else { return false }
        lastPersistenceError = nil
        _ = removeEvent(id: id, journalDelivery: false)
        return lastPersistenceError == nil
    }

    /// Explicit deletion is irreversible; review corrections use reversible overlays instead.
    @discardableResult
    public func removeEvent(id: UUID) -> Bool {
        removeEvent(id: id, journalDelivery: true)
    }

    private func removeEvent(id: UUID, journalDelivery: Bool) -> Bool {
        let hadEvent = events.contains { $0.id == id }
        var next = snapshot
        let inserted = next.deletedEventIDs.insert(id).inserted
        next.deletedEventIDs.insert(canonicalEventID(id))
        next.events.removeAll { $0.id == id || $0.id == canonicalEventID(id) }
        if journalDelivery, inserted {
            next.pendingEventMutations?.append(.init(id: UUID(), event: nil, deletedID: id))
        }
        guard commit(next) else { return false }
        if journalDelivery, enqueueDeletion != nil { _ = retryPendingEventMutations() }
        return hadEvent
    }

    public func removeAll() {
        var next = snapshot
        let ids = Set(rawEvents.map(\.id) + events.map(\.id)).subtracting(next.deletedEventIDs)
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            next.pendingEventMutations?.append(.init(id: UUID(), event: nil, deletedID: id))
        }
        next.deletedEventIDs.formUnion(ids)
        next.events.removeAll()
        guard commit(next) else { return }
        if enqueueDeletion != nil { _ = retryPendingEventMutations() }
    }

    /// Local changes and their outbound intent share the same atomic snapshot.
    /// Incoming mutations deliberately bypass this journal to avoid sync loops.
    public func configureEventDelivery(
        enqueueEvent: @escaping (SmokingEvent) -> Bool,
        enqueueDeletion: @escaping (UUID) -> Bool
    ) {
        self.enqueueEvent = enqueueEvent
        self.enqueueDeletion = enqueueDeletion
        _ = retryPendingEventMutations()
    }

    /// A queued payload can be repeated after interruption. Retire its intent only
    /// after the transport confirms that its own outbox was durably saved.
    @discardableResult
    public func retryPendingEventMutations() -> Bool {
        guard loadFailed == false, isSendingEventMutations == false else { return false }
        guard pendingEventMutations.isEmpty == false else {
            lastPersistenceError = nil
            return true
        }
        guard let enqueueEvent, let enqueueDeletion else {
            lastPersistenceError = "The cigarette log is saved locally. Companion sync is not ready yet."
            return false
        }
        isSendingEventMutations = true
        defer { isSendingEventMutations = false }
        for mutation in pendingEventMutations {
            let queued: Bool
            if let event = mutation.event, mutation.deletedID == nil { queued = enqueueEvent(event) }
            else if let id = mutation.deletedID, mutation.event == nil { queued = enqueueDeletion(id) }
            else {
                lastPersistenceError = "A saved cigarette sync operation is unreadable."
                return false
            }
            guard queued else {
                lastPersistenceError = "The cigarette log is saved locally. Its companion sync queue could not be saved; please retry."
                return false
            }
            var next = snapshot
            next.pendingEventMutations?.removeAll { $0.id == mutation.id }
            guard commit(next) else { return false }
        }
        lastPersistenceError = nil
        return true
    }

    /// Originals are retained even when a review hides them. A winning correction
    /// can restore its own scope without undoing an explicit event deletion.
    public func originalEvents(for ids: [UUID]) -> [SmokingEvent] {
        let requested = Set(ids)
        return rawEvents.filter { requested.contains($0.id) }
    }

    /// Rebuilds the derived log atomically from the canonical review journal.
    /// Repeating this after any crash boundary is safe and does not add tombstones.
    @discardableResult
    public func applyCorrections(_ reviews: [DetectionReview]) -> Bool {
        guard reviews.allSatisfy(\.hasValidDates) else {
            lastPersistenceError = "A saved review contains an invalid date."
            return false
        }
        var next = snapshot
        var known = Set(next.events.map(\.id))
        for review in reviews {
            let scope = Set(review.eventIDs)
            for original in review.eventSnapshots where scope.contains(original.id) {
                guard let original = Self.validated(original) else {
                    lastPersistenceError = "A saved review contains an invalid original event."
                    return false
                }
                var retainedID = original.id
                if original.source == .automatic {
                    if next.automaticEventTimes[original.id] == nil,
                       let matched = Self.automaticSessionID(matching: original, in: next) {
                        retainedID = matched
                        next.eventAliases?[original.id] = matched
                    }
                    let start = original.motionSessionStartedAt ?? original.timestamp
                    next.automaticEventTimes[retainedID] = max(next.automaticEventTimes[retainedID] ?? original.timestamp, original.timestamp)
                    let retainedStart = min(next.automaticSessionStarts?[retainedID] ?? start, start)
                    next.automaticSessionStarts?[retainedID] = retainedStart
                }
                if retainedID == original.id, known.insert(original.id).inserted { next.events.append(original) }
            }
        }
        func resolved(_ id: UUID) -> UUID {
            var result = id
            var seen = Set<UUID>()
            while seen.insert(result).inserted, let alias = next.eventAliases?[result] { result = alias }
            return result
        }
        let deleted = Set(next.deletedEventIDs.map(resolved))
        let effective = DetectionReview.effectiveScopes(reviews, resolvingEventID: resolved)
        for review in effective where review.correction != nil && review.decision != .pending {
            guard review.eventIDs.allSatisfy({ known.contains(resolved($0)) || deleted.contains(resolved($0)) }) else {
                lastPersistenceError = "Waiting for the original detections to finish syncing. The saved review will retry automatically."
                return false
            }
        }
        next.events.sort(by: Self.eventOrder)
        next.correctionReviews = reviews.sorted { $0.id.uuidString < $1.id.uuidString }
        return commit(next)
    }

	/// Legacy point lookup. New writes compare complete supporting intervals.
	public func hasRecordedAutomaticSession(near date: Date, tolerance: TimeInterval = 30) -> Bool {
		guard Self.isValid(date), tolerance.isFinite, tolerance > 0 else { return false }
		return automaticEventTimes.contains { id, end in
			date >= (automaticSessionStarts[id] ?? end).addingTimeInterval(-tolerance)
				&& date <= end.addingTimeInterval(tolerance)
		}
	}

    private func automaticSessionID(matching event: SmokingEvent) -> UUID? {
        if let alias = eventAliases[event.id] { return canonicalEventID(alias) }
        return Self.automaticSessionID(matching: event, in: snapshot)
    }

    private static func automaticSessionID(matching event: SmokingEvent, in saved: Snapshot) -> UUID? {
        if saved.automaticEventTimes[event.id] != nil { return event.id }
        let start = event.motionSessionStartedAt ?? event.timestamp
        return saved.automaticEventTimes.keys.sorted { $0.uuidString < $1.uuidString }.first { id in
            guard let end = saved.automaticEventTimes[id] else { return false }
            let savedStart = saved.automaticSessionStarts?[id] ?? end
            return start <= end.addingTimeInterval(30) && event.timestamp >= savedStart.addingTimeInterval(-30)
        }
    }

    public func canonicalEventID(_ id: UUID) -> UUID {
        var result = id
        var visited = Set<UUID>()
        while visited.insert(result).inserted, let alias = eventAliases[result] { result = alias }
        return result
    }

	public func events(on day: Date) -> [SmokingEvent] {
		guard Self.isValid(day) else { return [] }
		let start = day.startOfDayInCurrentCalendar
		let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
		return events.filter { $0.timestamp >= start && $0.timestamp < end }
	}

	public func dailyCount(on day: Date) -> Int {
		events(on: day).count
	}

	/// Returns consecutive smoke-free calendar days as of the supplied time.
	///
	/// The search is bounded by the oldest stored event. With no history there is not yet
	/// enough evidence to claim a smoke-free streak, so the result is zero.
	public func streakSmokeFreeDays(considering day: Date = Date()) -> Int {
		guard Self.isValid(day), events.isEmpty == false else { return 0 }
		let calendar = Calendar.current
		let targetDay = day.startOfDayInCurrentCalendar
		guard let latestDay = events.reversed().first(where: {
			$0.timestamp <= day
		})?.timestamp.startOfDayInCurrentCalendar else { return 0 }
		return max(0, calendar.dateComponents([.day], from: latestDay, to: targetDay).day ?? 0)
	}

	/// Naive money-saved estimate based on cost per cigarette
	public func estimatedMoneySaved(costPerCigarette: Double = 0.6) -> Double {
		// Assumes that each prevented event compared to user's baseline yields savings.
		// For now, we simply multiply streak days by (dailyLimit * cost).
		guard costPerCigarette.isFinite, costPerCigarette > 0 else { return 0 }
		let baselinePerDay = max(0, userDefaults.integer(forKey: "baselineCigsPerDay"))
		let days = streakSmokeFreeDays()
		let estimate = Double(baselinePerDay) * Double(days) * costPerCigarette
		return estimate.isFinite ? estimate : 0
	}

    private var snapshot: Snapshot {
        Snapshot(events: rawEvents, deletedEventIDs: deletedEventIDs,
                 automaticEventTimes: automaticEventTimes, automaticSessionStarts: automaticSessionStarts,
                 correctionReviews: correctionReviews, eventAliases: eventAliases, pendingEventMutations: pendingEventMutations)
    }

    private func load() {
        do {
            let fileData = try snapshotFile?.load()
            let data = fileData ?? userDefaults.data(forKey: storageKey)
            if let data, let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
                let pending = saved.pendingEventMutations ?? []
                guard Set(pending.map(\.id)).count == pending.count,
                      pending.allSatisfy({ mutation in
                          if let event = mutation.event { return mutation.deletedID == nil && Self.validated(event) == event }
                          return mutation.deletedID != nil
                      }) else { throw CocoaError(.fileReadCorruptFile) }
                install(saved)
                return
            }
            if fileData != nil {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let data = userDefaults.data(forKey: automaticTimesKey),
               let decoded = try? JSONDecoder().decode([UUID: Date].self, from: data) {
                automaticEventTimes = decoded.filter { Self.isValid($0.value) }
            }
            if let data = userDefaults.data(forKey: deletedStorageKey),
               let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
                deletedEventIDs = Set(decoded)
            }
            if let data {
                guard let decoded = try? JSONDecoder().decode([SmokingEvent].self, from: data) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                var legacy = snapshot
                legacy.events = decoded
                install(legacy)
            }
        } catch {
            loadFailed = true
            lastPersistenceError = "Could not read the saved cigarette log: \(error.localizedDescription)"
        }
    }

    private func install(_ saved: Snapshot) {
        deletedEventIDs = saved.deletedEventIDs
        eventAliases = saved.eventAliases ?? [:]
        pendingEventMutations = saved.pendingEventMutations ?? []
        automaticEventTimes = saved.automaticEventTimes.filter { Self.isValid($0.value) }
        automaticSessionStarts = (saved.automaticSessionStarts ?? [:]).filter {
            Self.isValid($0.value) && $0.value <= (automaticEventTimes[$0.key] ?? .distantPast)
        }
        var seen = Set<UUID>()
        rawEvents = saved.events.compactMap(Self.validated).filter { seen.insert($0.id).inserted }.sorted(by: Self.eventOrder)
        correctionReviews = (saved.correctionReviews ?? []).filter(\.hasValidDates)
        for event in rawEvents where event.source == .automatic {
            automaticEventTimes[event.id] = max(automaticEventTimes[event.id] ?? event.timestamp, event.timestamp)
            let start = event.motionSessionStartedAt ?? event.timestamp
            automaticSessionStarts[event.id] = min(automaticSessionStarts[event.id] ?? start, start)
        }
        publishDerivedEvents()
    }

    private func publishDerivedEvents() {
        var excluded = deletedEventIDs.union(deletedEventIDs.map(canonicalEventID))
        let effective = DetectionReview.effectiveScopes(correctionReviews, resolvingEventID: canonicalEventID).filter { $0.correction != nil && $0.decision != .pending }
        for review in effective {
            let target = review.decision == .accurate ? review.originalCount : review.displayCount
            excluded.formUnion(review.eventIDs.dropFirst(max(0, target)).map(canonicalEventID))
        }
        var result = rawEvents.filter { excluded.contains($0.id) == false }
        var seen = Set(result.map(\.id))
        for review in effective {
            let count = max(0, review.displayCount - review.originalCount)
            guard review.decision == .adjusted, count > 0 else { continue }
            let duration = max(0, review.windowEnd.timeIntervalSince(review.windowStart))
            for index in 0..<count {
                let id = review.correctionEventID(at: index)
                guard deletedEventIDs.contains(id) == false, seen.insert(id).inserted else { continue }
                let fraction = Double(index + 1) / Double(count + 1)
                result.append(SmokingEvent(id: id, timestamp: review.windowStart.addingTimeInterval(duration * fraction),
                    source: .manual, notes: "Added while adjusting a Watch detection summary."))
            }
        }
        result.sort(by: Self.eventOrder)
        if events != result { events = result }
    }

    @discardableResult
    private func commit(_ next: Snapshot) -> Bool {
        guard loadFailed == false else { return false }
        if next == snapshot { lastPersistenceError = nil; return true }
        do {
            let data = try JSONEncoder().encode(next)
            if let snapshotWriter { try snapshotWriter(data) }
            else if let snapshotFile { try snapshotFile.write(data) }
            else { userDefaults.set(data, forKey: storageKey) }
            install(next)
            lastPersistenceError = nil
            return true
        } catch {
            lastPersistenceError = "Could not save the cigarette log: \(error.localizedDescription)"
            return false
        }
    }

    private static func eventOrder(_ lhs: SmokingEvent, _ rhs: SmokingEvent) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id.uuidString < rhs.id.uuidString : lhs.timestamp < rhs.timestamp
    }

	private static func isValid(_ date: Date) -> Bool {
		date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
	}

	private static func validated(_ event: SmokingEvent) -> SmokingEvent? {
		guard isValid(event.timestamp) else { return nil }
		let heartRate = event.heartRate.flatMap { $0.isFinite && $0 > 0 && $0 <= 300 ? $0 : nil }
		let sessionStart = event.motionSessionStartedAt.flatMap {
			event.source == .automatic && isValid($0) && $0 <= event.timestamp ? $0 : nil
		}
		return SmokingEvent(id: event.id, timestamp: event.timestamp, source: event.source,
		                    heartRate: heartRate, notes: event.notes, motionSessionStartedAt: sessionStart)
	}
}
