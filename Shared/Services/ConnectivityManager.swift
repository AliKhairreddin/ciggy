import Foundation
import WatchConnectivity
import Combine

/// Simple wrapper around WCSession for sending/receiving smoking events between iPhone and Watch.
public final class ConnectivityManager: NSObject, ObservableObject, Sendable {
	public static let shared = ConnectivityManager()

	private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
	public let incomingEvent = PassthroughSubject<SmokingEvent, Never>()

	private override init() {
		super.init()
		session?.delegate = self
		session?.activate()
	}

	public func send(event: SmokingEvent) {
		guard let session else { return }
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		if let data = try? encoder.encode(event) {
			let payload: [String: Any] = ["type": "event", "data": data]
			if session.isReachable {
				session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
			} else {
				session.transferUserInfo(payload)
			}
		}
	}
}

extension ConnectivityManager: WCSessionDelegate {
	public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

	#if os(iOS)
	public func sessionDidBecomeInactive(_ session: WCSession) {}
	public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
	#endif

	public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
		handle(message)
	}

	public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
		handle(userInfo)
	}

	private func handle(_ payload: [String: Any]) {
		guard let type = payload["type"] as? String, type == "event",
				let data = payload["data"] as? Data else { return }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		if let event = try? decoder.decode(SmokingEvent.self, from: data) {
			DispatchQueue.main.async { self.incomingEvent.send(event) }
		}
	}
}


