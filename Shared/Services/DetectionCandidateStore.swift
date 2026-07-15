import Combine
import Foundation

/// Persists the one candidate awaiting review so notification-driven relaunches can restore it.
@MainActor
public final class DetectionCandidateStore: ObservableObject {
	@Published public private(set) var pendingCandidate: DetectionCandidate?

	private let userDefaults: UserDefaults
	private let storageKey: String

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionCandidateStore.pending.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		if let data = userDefaults.data(forKey: storageKey) {
			pendingCandidate = try? JSONDecoder().decode(DetectionCandidate.self, from: data)
		}
	}

	@discardableResult
	public func present(_ candidate: DetectionCandidate) -> Bool {
		guard pendingCandidate == nil else { return false }
		pendingCandidate = candidate
		persist()
		return true
	}

	@discardableResult
	public func resolve(candidateID: UUID) -> Bool {
		guard pendingCandidate?.id == candidateID else { return false }
		pendingCandidate = nil
		persist()
		return true
	}

	private func persist() {
		guard let pendingCandidate else {
			userDefaults.removeObject(forKey: storageKey)
			return
		}
		if let data = try? JSONEncoder().encode(pendingCandidate) {
			userDefaults.set(data, forKey: storageKey)
		}
	}
}
