import Combine
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// Main-actor wrapper around WatchConnectivity for events and shared settings.
@MainActor
public final class ConnectivityManager: NSObject, ObservableObject {
	public static let shared = ConnectivityManager()

	public let incomingEvent = PassthroughSubject<SmokingEvent, Never>()
	public let incomingDeletedEventID = PassthroughSubject<UUID, Never>()
	public let incomingReview = PassthroughSubject<DetectionReview, Never>()
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
	private let transportStore = ConnectivityTransportStore()
	private var isIncomingDeliveryReady = false
	private var liveTransfers: Set<UUID> = []
	private let recordingTransfersKey = "Ciggy.connectivity.recordingTransfers.v1"
	private var pendingRecordingPaths: [String] = []

	private override init() {
		super.init()
		pendingRecordingPaths = UserDefaults.standard.stringArray(forKey: recordingTransfersKey) ?? []
		session?.delegate = self
		session?.activate()
		refreshSessionState()
	}

	public func send(event: SmokingEvent) {
		guard let payload = encodedPayload(type: "event", value: event) else { return }
		queueDurable(payload)
	}

	public func sendDeletedEvent(id: UUID) {
		guard let payload = encodedPayload(type: "eventDeletion", value: id) else { return }
		queueDurable(payload)
	}

	public func send(review: DetectionReview) {
		guard let payload = encodedPayload(type: "detectionReview", value: review) else { return }
		queueDurable(payload)
	}

	public func send(settings: UserSettings) {
		latestSettingsPayload = encodedPayload(type: "settings", value: settings)
		settingsSyncNeedsRetry = true
		flushLatestSettings()
	}

	/// Call after repositories subscribe, including after a background-only launch.
	public func activateIncomingDelivery() {
		isIncomingDeliveryReady = true
		flushIncoming()
		resumeSync()
	}

	public func resumeSync() {
		refreshSessionState()
		flushLatestSettings()
		flushPendingDurablePayloads()
		flushRecordingTransfers()
	}

	/// Explicit export only; raw wrist recordings are never uploaded automatically.
	public func sendMotionRecording(at url: URL) {
		guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return }
		if pendingRecordingPaths.contains(url.path) == false {
			pendingRecordingPaths.append(url.path)
			UserDefaults.standard.set(pendingRecordingPaths, forKey: recordingTransfersKey)
		}
		flushRecordingTransfers()
	}

	private func flushRecordingTransfers() {
		guard let session, session.activationState == .activated else { return }
		#if !targetEnvironment(simulator)
		let outstanding = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["recordingPath"] as? String })
		for path in pendingRecordingPaths where outstanding.contains(path) == false {
			guard FileManager.default.fileExists(atPath: path) else { continue }
			session.transferFile(URL(fileURLWithPath: path), metadata: ["type": "motionRecording", "recordingPath": path])
		}
		#endif
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

	private func queueDurable(_ payload: [String: Any]) {
		guard let type = payload["type"] as? String, let data = payload["data"] as? Data else { return }
		transportStore.enqueue(.init(type: type, data: data))
		flushPendingDurablePayloads()
	}

	private func flushPendingDurablePayloads() {
		guard let session, session.activationState == .activated else { return }
		let outstandingIDs = Set(session.outstandingUserInfoTransfers.compactMap {
			($0.userInfo["transportID"] as? String).flatMap(UUID.init(uuidString:))
		})
		for envelope in transportStore.outgoing {
			let payload: [String: Any] = ["type": envelope.type, "data": envelope.data, "transportID": envelope.id.uuidString]
			if session.isReachable, liveTransfers.insert(envelope.id).inserted {
				session.sendMessage(payload, replyHandler: { [weak self] reply in
					let acknowledged = reply["acknowledged"] as? String == envelope.id.uuidString
					Task { @MainActor [weak self] in
						self?.liveTransfers.remove(envelope.id)
						if acknowledged { self?.transportStore.acknowledge(id: envelope.id) }
					}
				}, errorHandler: { [weak self] error in
					Task { @MainActor [weak self] in
						self?.liveTransfers.remove(envelope.id)
						self?.lastSyncError = error.localizedDescription
					}
				})
			}
			#if !targetEnvironment(simulator)
			if outstandingIDs.contains(envelope.id) == false { session.transferUserInfo(payload) }
			#endif
		}
	}

	private func flushIncoming() {
		guard isIncomingDeliveryReady else { return }
		for envelope in transportStore.incoming {
			deliver(type: envelope.type, data: envelope.data)
			transportStore.didDeliver(id: envelope.id)
		}
	}

	private func deliver(type: String, data: Data) {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		switch type {
		case "event":
			if let value = try? decoder.decode(SmokingEvent.self, from: data) { incomingEvent.send(value) }
		case "eventDeletion":
			if let value = try? decoder.decode(UUID.self, from: data) { incomingDeletedEventID.send(value) }
		case "detectionReview":
			if let value = try? decoder.decode(DetectionReview.self, from: data) { incomingReview.send(value) }
		case "settings":
			if let value = try? decoder.decode(UserSettings.self, from: data) { incomingSettings.send(value) }
		default: break
		}
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
			self?.flushPendingDurablePayloads()
			self?.flushRecordingTransfers()
		}
	}

	nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
		Task { @MainActor [weak self] in
			self?.refreshSessionState()
			guard self?.isReachable == true else { return }
			self?.flushLatestSettings()
			self?.flushPendingDurablePayloads()
			self?.flushRecordingTransfers()
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

	nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any],
	                                replyHandler: @escaping ([String: Any]) -> Void) {
		handle(message, replyHandler: replyHandler)
	}

	nonisolated public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
		guard let value = userInfoTransfer.userInfo["transportID"] as? String,
		      let id = UUID(uuidString: value) else { return }
		let message = error?.localizedDescription
		Task { @MainActor [weak self] in
			if let message { self?.lastSyncError = message }
			else { self?.transportStore.acknowledge(id: id) }
		}
	}

	nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
		guard file.metadata?["type"] as? String == "motionRecording",
		      let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
		      size <= 10 * 1_024 * 1_024,
		      let data = try? Data(contentsOf: file.fileURL) else { return }
		// Persist before returning, then validate/import on the main actor. A later
		// app launch recovers any inbox file left by an interrupted import.
		do { try MotionRecordingStore.preserveIncomingRecording(data: data) }
		catch {
			Task { @MainActor [weak self] in self?.lastSyncError = "Could not save the incoming motion recording." }
			return
		}
		Task { @MainActor [weak self] in
			MotionRecordingStore.shared.recoverIncomingRecordings()
			if let error = MotionRecordingStore.shared.lastError { self?.lastSyncError = error }
		}
	}

	nonisolated public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
		guard let path = fileTransfer.file.metadata?["recordingPath"] as? String else { return }
		let message = error?.localizedDescription
		Task { @MainActor [weak self] in
			guard let self else { return }
			if let message { self.lastSyncError = message; return }
			self.pendingRecordingPaths.removeAll { $0 == path }
			UserDefaults.standard.set(self.pendingRecordingPaths, forKey: self.recordingTransfersKey)
		}
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

	nonisolated private func handle(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
		guard let type = payload["type"] as? String,
		      let data = payload["data"] as? Data else { replyHandler?([:]); return }
		let id = (payload["transportID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
		let envelope = ConnectivityEnvelope(id: id, type: type, data: data)
		Task { @MainActor [weak self] in
			guard let self else { replyHandler?([:]); return }
			self.transportStore.receive(envelope)
			self.flushIncoming()
			replyHandler?(["acknowledged": id.uuidString])
		}
	}
}
#else
/// Host-platform fallback used by unit tests; phone/watch builds use WatchConnectivity above.
@MainActor
public final class ConnectivityManager: ObservableObject {
	public static let shared = ConnectivityManager()
	public let incomingEvent = PassthroughSubject<SmokingEvent, Never>()
	public let incomingDeletedEventID = PassthroughSubject<UUID, Never>()
	public let incomingReview = PassthroughSubject<DetectionReview, Never>()
	public let incomingSettings = CurrentValueSubject<UserSettings?, Never>(nil)
	@Published public private(set) var isActivated = false
	@Published public private(set) var isReachable = false
	@Published public private(set) var isCounterpartAppInstalled = false
	@Published public private(set) var lastSyncError: String?
	public var isLiveSyncAvailable: Bool { false }

	private init() {}

	public func send(event: SmokingEvent) {}
	public func sendDeletedEvent(id: UUID) {}
	public func send(review: DetectionReview) {}
	public func send(settings: UserSettings) {}
	public func activateIncomingDelivery() {}
	public func resumeSync() {}
	public func sendMotionRecording(at url: URL) {}
}
#endif
