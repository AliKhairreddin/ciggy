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
	@Published public private(set) var isActivated = false
	@Published public private(set) var isReachable = false
	@Published public private(set) var isCounterpartAppInstalled = false
	@Published public private(set) var lastSyncError: String?

	/// Reachability means both companion apps are currently running and can use
	/// an immediate message. Durable transfers still work when this is false.
	public var isLiveSyncAvailable: Bool { isActivated && isReachable }

	private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
	private var latestSettingsPayload: [String: Any]?
	private var settingsSyncNeedsRetry = false
	private var pendingEventPayloads: [[String: Any]] = []

	private override init() {
		super.init()
		session?.delegate = self
		session?.activate()
		refreshSessionState()
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
		      let latestSettingsPayload else { return }
		sendLiveIfReachable(latestSettingsPayload)
		guard settingsSyncNeedsRetry else { return }
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

	private func sendLiveIfReachable(_ payload: [String: Any]) {
		guard let session,
		      session.activationState == .activated,
		      session.isReachable else { return }
		session.sendMessage(payload, replyHandler: nil) { [weak self] error in
			Task { @MainActor [weak self] in
				self?.lastSyncError = error.localizedDescription
				self?.refreshSessionState()
			}
		}
	}

	private func flushPendingEvents() {
		guard let session, session.activationState == .activated else { return }
		if session.isReachable {
			pendingEventPayloads.forEach { sendLiveIfReachable($0) }
		}
		#if targetEnvironment(simulator)
		// Simulator does not deliver transferUserInfo. Keep events in memory until
		// the companion becomes reachable, then complete via sendMessage.
		guard session.isReachable else { return }
		#else
		// Physical devices get durable background delivery in addition to the
		// immediate foreground message. EventRepository de-duplicates by UUID.
		pendingEventPayloads.forEach { session.transferUserInfo($0) }
		#endif
		pendingEventPayloads.removeAll()
	}

	private func refreshSessionState() {
		isActivated = session?.activationState == .activated
		guard isActivated, let session else {
			isReachable = false
			isCounterpartAppInstalled = false
			return
		}
		// WatchConnectivity logs a runtime warning when reachability and pairing
		// properties are read before activation has completed.
		isReachable = session.isReachable
		#if os(iOS)
		isCounterpartAppInstalled = session.isPaired && session.isWatchAppInstalled
		#elseif os(watchOS)
		isCounterpartAppInstalled = session.isCompanionAppInstalled
		#endif
		if isLiveSyncAvailable {
			lastSyncError = nil
		}
	}
}

extension ConnectivityManager: WCSessionDelegate {
	nonisolated public func session(
		_ session: WCSession,
		activationDidCompleteWith activationState: WCSessionActivationState,
		error: Error?
	) {
		Task { @MainActor [weak self] in
			self?.refreshSessionState()
			guard activationState == .activated else { return }
			self?.flushLatestSettings()
			self?.flushPendingEvents()
		}
	}

	nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
		Task { @MainActor [weak self] in
			self?.refreshSessionState()
			guard self?.isReachable == true else { return }
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
		Task { @MainActor [weak self] in
			self?.refreshSessionState()
			self?.retryLatestSettings()
		}
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
	@Published public private(set) var isActivated = false
	@Published public private(set) var isReachable = false
	@Published public private(set) var isCounterpartAppInstalled = false
	@Published public private(set) var lastSyncError: String?
	public var isLiveSyncAvailable: Bool { false }

	private init() {}

	public func send(event: SmokingEvent) {}
	public func send(settings: UserSettings) {}
}
#endif
