import Combine
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// Main-actor wrapper around WatchConnectivity for events and shared settings.
@MainActor
public final class ConnectivityManager: NSObject, ObservableObject {
	public static let shared = ConnectivityManager()

	public let incomingEvent = PassthroughSubject<SmokingEvent, Never>()
	public let incomingSettings = CurrentValueSubject<UserSettings?, Never>(nil)

	private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
	private var latestSettingsPayload: [String: Any]?
	private var settingsSyncNeedsRetry = false
	private var pendingEventPayloads: [[String: Any]] = []

	private override init() {
		super.init()
		session?.delegate = self
		session?.activate()
	}

	public func send(event: SmokingEvent) {
		guard let payload = encodedPayload(type: "event", value: event) else { return }
		pendingEventPayloads.append(payload)
		flushPendingEvents()
	}

	public func send(settings: UserSettings) {
		latestSettingsPayload = encodedPayload(type: "settings", value: settings)
		settingsSyncNeedsRetry = true
		flushLatestSettings()
	}

	private func encodedPayload<Value: Encodable>(type: String, value: Value) -> [String: Any]? {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		guard let data = try? encoder.encode(value) else { return nil }
		return ["type": type, "data": data]
	}

	private func flushLatestSettings() {
		guard let session,
		      session.activationState == .activated,
		      let latestSettingsPayload,
		      settingsSyncNeedsRetry else { return }
		do {
			try session.updateApplicationContext(latestSettingsPayload)
			settingsSyncNeedsRetry = false
		} catch {
			settingsSyncNeedsRetry = true
		}
	}

	private func retryLatestSettings() {
		settingsSyncNeedsRetry = latestSettingsPayload != nil
		flushLatestSettings()
	}

	private func flushPendingEvents() {
		guard let session, session.activationState == .activated else { return }
		pendingEventPayloads.forEach { session.transferUserInfo($0) }
		pendingEventPayloads.removeAll()
	}
}

extension ConnectivityManager: WCSessionDelegate {
	nonisolated public func session(
		_ session: WCSession,
		activationDidCompleteWith activationState: WCSessionActivationState,
		error: Error?
	) {
		guard activationState == .activated else { return }
		Task { @MainActor [weak self] in
			self?.flushLatestSettings()
			self?.flushPendingEvents()
		}
	}

	#if os(iOS)
	nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

	nonisolated public func sessionDidDeactivate(_ session: WCSession) {
		session.activate()
	}

	nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
		Task { @MainActor [weak self] in self?.retryLatestSettings() }
	}
	#endif

	nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		handle(message)
	}

	nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
		handle(userInfo)
	}

	nonisolated public func session(
		_ session: WCSession,
		didReceiveApplicationContext applicationContext: [String: Any]
	) {
		handle(applicationContext)
	}

	nonisolated private func handle(_ payload: [String: Any]) {
		guard let type = payload["type"] as? String,
		      let data = payload["data"] as? Data else { return }

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		switch type {
		case "event":
			guard let event = try? decoder.decode(SmokingEvent.self, from: data) else { return }
			Task { @MainActor [weak self] in self?.incomingEvent.send(event) }
		case "settings":
			guard let settings = try? decoder.decode(UserSettings.self, from: data) else { return }
			Task { @MainActor [weak self] in self?.incomingSettings.send(settings) }
		default:
			break
		}
	}
}
#else
/// Host-platform fallback used by unit tests; phone/watch builds use WatchConnectivity above.
@MainActor
public final class ConnectivityManager: ObservableObject {
	public static let shared = ConnectivityManager()
	public let incomingEvent = PassthroughSubject<SmokingEvent, Never>()
	public let incomingSettings = CurrentValueSubject<UserSettings?, Never>(nil)

	private init() {}

	public func send(event: SmokingEvent) {}
	public func send(settings: UserSettings) {}
}
#endif
