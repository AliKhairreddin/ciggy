import Foundation

/// A persisted transport envelope, independent of WatchConnectivity for tests.
public struct ConnectivityEnvelope: Codable, Equatable, Identifiable, Sendable {
	public let id: UUID
	public let type: String
	public let data: Data
	public init(id: UUID = UUID(), type: String, data: Data) {
		self.id = id; self.type = type; self.data = data
	}
}

/// Keep outgoing mutations until a system transfer completes or the other app
/// acknowledges persistence. Keep incoming mutations until stores are bound.
@MainActor
public final class ConnectivityTransportStore {
	private struct State: Codable {
		var outgoing: [ConnectivityEnvelope] = []
		var incoming: [ConnectivityEnvelope] = []
	}
	private var state: State
	private let defaults: UserDefaults
	private let key: String
	public var outgoing: [ConnectivityEnvelope] { state.outgoing }
	public var incoming: [ConnectivityEnvelope] { state.incoming }

	public init(defaults: UserDefaults = .standard, key: String = "Ciggy.connectivity.transport.v1") {
		self.defaults = defaults; self.key = key
		state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
	}
	public func enqueue(_ envelope: ConnectivityEnvelope) {
		guard state.outgoing.contains(where: { $0.id == envelope.id }) == false else { return }
		state.outgoing.append(envelope); save()
	}
	public func acknowledge(id: UUID) {
		state.outgoing.removeAll { $0.id == id }; save()
	}
	public func receive(_ envelope: ConnectivityEnvelope) {
		guard state.incoming.contains(where: { $0.id == envelope.id }) == false else { return }
		state.incoming.append(envelope); save()
	}
	public func didDeliver(id: UUID) {
		state.incoming.removeAll { $0.id == id }; save()
	}
	private func save() {
		if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
	}
}
