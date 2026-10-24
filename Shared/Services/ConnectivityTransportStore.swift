import Foundation

/// A persisted transport envelope, independent of WatchConnectivity for tests.
public struct ConnectivityEnvelope: Codable, Equatable, Identifiable, Sendable {
	public let id: UUID
	public let type: String
	public let data: Data
	public init(id: UUID = UUID(), type: String, data: Data) {
		self.id = id; self.type = type; self.data = data
	}

	/// System transfer completion is not proof that the recipient saved a mutation.
	public var requiresDurableReceipt: Bool {
		["event", "eventDeletion", "detectionReview", "reviewCorrection.v2"].contains(type)
	}
}

/// Atomically retain outgoing mutations until the recipient saves its inbox, and
/// incoming mutations until their effects are durable. Every step is replayable.
@MainActor
public final class ConnectivityTransportStore {
	private struct State: Codable {
		var outgoing: [ConnectivityEnvelope] = []
		var incoming: [ConnectivityEnvelope] = []
		var latestSettings: ConnectivityEnvelope?
	}
	private var state = State()
	private let defaults: UserDefaults
	private let key: String
	private let snapshot: DurableSnapshotFile?
	private var loadFailed = false
	public private(set) var lastPersistenceError: String?
	public var outgoing: [ConnectivityEnvelope] { state.outgoing }
	public var incoming: [ConnectivityEnvelope] { state.incoming }
	public var latestSettings: ConnectivityEnvelope? { state.latestSettings }

	public init(defaults: UserDefaults = .standard, key: String = "Ciggy.connectivity.transport.v1", snapshotURL: URL? = nil) {
		self.defaults = defaults; self.key = key
		self.snapshot = (snapshotURL ?? (defaults === UserDefaults.standard ? DurableSnapshotFile.defaultURL(name: key) : nil)).map(DurableSnapshotFile.init)
		do {
			if let data = try snapshot?.load() ?? defaults.data(forKey: key) {
				state = try JSONDecoder().decode(State.self, from: data)
			}
		} catch {
			loadFailed = true
			lastPersistenceError = "Could not read saved sync changes. \(error.localizedDescription)"
		}
	}

	@discardableResult public func enqueue(_ envelope: ConnectivityEnvelope) -> Bool {
		guard hasConsistentIdentity(envelope, in: state.outgoing) else { return false }
		return mutate { state in
			guard state.outgoing.contains(where: {
				$0.id == envelope.id || ($0.type == envelope.type && $0.data == envelope.data)
			}) == false else { return }
			state.outgoing.append(envelope)
		}
	}

	/// Only replace ephemeral control/status messages. Event mutations keep their full queue.
	@discardableResult public func enqueueLatest(_ envelope: ConnectivityEnvelope) -> Bool {
		guard ["historyRefreshRequest", "trackingStatus"].contains(envelope.type) else { return enqueue(envelope) }
		return mutate { state in
			state.outgoing.removeAll { $0.type == envelope.type }
			state.outgoing.append(envelope)
		}
	}
	@discardableResult public func acknowledge(id: UUID) -> Bool {
		mutate { $0.outgoing.removeAll { $0.id == id } }
	}
	@discardableResult public func receive(_ envelope: ConnectivityEnvelope) -> Bool {
		guard hasConsistentIdentity(envelope, in: state.incoming) else { return false }
		return mutate { state in
			guard state.incoming.contains(where: { $0.id == envelope.id }) == false else { return }
			state.incoming.append(envelope)
		}
	}
	@discardableResult public func didDeliver(id: UUID) -> Bool {
		mutate { $0.incoming.removeAll { $0.id == id } }
	}
	/// Application context is last-write-wins, but must survive a pre-activation exit.
	@discardableResult public func replaceSettings(_ envelope: ConnectivityEnvelope) -> Bool {
		guard envelope.type == "settings" else { return false }
		return mutate { $0.latestSettings = envelope }
	}
	@discardableResult public func clearSettings() -> Bool {
		mutate { $0.latestSettings = nil }
	}

	private func hasConsistentIdentity(_ envelope: ConnectivityEnvelope, in saved: [ConnectivityEnvelope]) -> Bool {
		if let existing = saved.first(where: { $0.id == envelope.id }), existing != envelope {
			lastPersistenceError = "A sync message reused an identifier with different contents. Saved changes were preserved."
			return false
		}
		return true
	}

	private func mutate(_ change: (inout State) -> Void) -> Bool {
		guard loadFailed == false else { return false } // Never overwrite unreadable saved changes.
		var next = state
		change(&next)
		do {
			let data = try JSONEncoder().encode(next)
			if let snapshot { try snapshot.write(data) } else { defaults.set(data, forKey: key) }
			state = next
			lastPersistenceError = nil
			return true
		} catch {
			lastPersistenceError = "Could not save sync changes. \(error.localizedDescription)"
			return false
		}
	}
}
