import Foundation
import Combine

/// In-memory + UserDefaults persisted repository for smoking events.
/// In later phases, this can sync with Firebase and CloudKit.
@MainActor
public final class EventRepository: ObservableObject {
	@Published public private(set) var events: [SmokingEvent] = []

	private let userDefaults: UserDefaults
	private let storageKey: String
	private let deletedStorageKey: String
	private var deletedEventIDs: Set<UUID> = []
	private var automaticEventTimes: [UUID: Date] = [:]
	private var automaticSessionStarts: [UUID: Date] = [:]
	private var automaticTimesKey: String { "\(storageKey).automaticTimes.v1" }
	private struct Snapshot: Codable {
		let events: [SmokingEvent]
		let deletedEventIDs: Set<UUID>
		let automaticEventTimes: [UUID: Date]
		let automaticSessionStarts: [UUID: Date]?
	}

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "EventRepository.events.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		self.deletedStorageKey = "\(storageKey).deleted.v1"
		load()
	}

	@discardableResult
	public func addEvent(_ event: SmokingEvent) -> Bool {
		guard let event = Self.validated(event) else { return false }
		if event.source == .automatic {
			// Compare the observed pattern, rather than blocking every event near
			// another timestamp. Retain matching evidence even after a correction.
			let matchedID = automaticSessionID(matching: event)
			let retainedID = matchedID ?? event.id
			let start = event.motionSessionStartedAt ?? event.timestamp
			let retainedStart = min(automaticSessionStarts[retainedID] ?? automaticEventTimes[retainedID] ?? start, start)
			let retainedEnd = max(automaticEventTimes[retainedID] ?? event.timestamp, event.timestamp)
			let changed = automaticSessionStarts[retainedID] != retainedStart || automaticEventTimes[retainedID] != retainedEnd
			automaticSessionStarts[retainedID] = retainedStart
			automaticEventTimes[retainedID] = retainedEnd
			if matchedID != nil || deletedEventIDs.contains(event.id) {
				if changed { save() }
				return false
			}
		}
		guard deletedEventIDs.contains(event.id) == false else { return false }
		guard events.contains(where: { $0.id == event.id }) == false else { return false }
		events.append(event)
		events.sort { $0.timestamp < $1.timestamp }
		save()
		return true
	}

	/// Persists a tombstone so a delayed duplicate transfer cannot restore a correction.
	@discardableResult
	public func removeEvent(id: UUID) -> Bool {
		let hadEvent = events.contains { $0.id == id }
		deletedEventIDs.insert(id)
		events.removeAll { $0.id == id }
		save()
		return hadEvent
	}

	public func removeAll() {
		deletedEventIDs.formUnion(events.map(\.id))
		events.removeAll()
		save()
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
		if automaticEventTimes[event.id] != nil { return event.id }
		let start = event.motionSessionStartedAt ?? event.timestamp
		// Small sensor timing differences are expected between fused motion and
		// accelerometer history. A distinct session break remains separate.
		return automaticEventTimes.keys.sorted { $0.uuidString < $1.uuidString }.first { id in
			guard let end = automaticEventTimes[id] else { return false }
			let savedStart = automaticSessionStarts[id] ?? end
			return start <= end.addingTimeInterval(30) && event.timestamp >= savedStart.addingTimeInterval(-30)
		}
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

	private func load() {
		if let data = userDefaults.data(forKey: storageKey),
		   let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
			deletedEventIDs = snapshot.deletedEventIDs
			automaticEventTimes = snapshot.automaticEventTimes.filter { Self.isValid($0.value) }
			automaticSessionStarts = (snapshot.automaticSessionStarts ?? [:]).filter {
				Self.isValid($0.value) && $0.value <= (automaticEventTimes[$0.key] ?? .distantPast)
			}
			loadEvents(snapshot.events)
			return
		}
		if let data = userDefaults.data(forKey: automaticTimesKey),
		   let decoded = try? JSONDecoder().decode([UUID: Date].self, from: data) {
			automaticEventTimes = decoded.filter { Self.isValid($0.value) }
		}
		if let deletedData = userDefaults.data(forKey: deletedStorageKey),
		   let decodedDeletedIDs = try? JSONDecoder().decode([UUID].self, from: deletedData) {
			deletedEventIDs = Set(decodedDeletedIDs)
		}
		guard let data = userDefaults.data(forKey: storageKey),
			let decoded = try? JSONDecoder().decode([SmokingEvent].self, from: data) else {
			events = []
			return
		}
		loadEvents(decoded)
	}

	private func loadEvents(_ decoded: [SmokingEvent]) {
		var seen = Set<UUID>()
		events = decoded.compactMap(Self.validated)
			.filter { deletedEventIDs.contains($0.id) == false }
			.filter { seen.insert($0.id).inserted }
			.sorted { $0.timestamp < $1.timestamp }
		for event in events where event.source == .automatic {
			automaticEventTimes[event.id] = max(automaticEventTimes[event.id] ?? event.timestamp, event.timestamp)
			let start = event.motionSessionStartedAt ?? event.timestamp
			automaticSessionStarts[event.id] = min(automaticSessionStarts[event.id] ?? start, start)
		}
	}

	private func save() {
		// Keep corrections and their session history in the same persisted value.
		// A terminated write cannot leave a new events array with old tombstones.
		let snapshot = Snapshot(events: events, deletedEventIDs: deletedEventIDs,
		                        automaticEventTimes: automaticEventTimes, automaticSessionStarts: automaticSessionStarts)
		if let data = try? JSONEncoder().encode(snapshot) {
			userDefaults.set(data, forKey: storageKey)
		}
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
