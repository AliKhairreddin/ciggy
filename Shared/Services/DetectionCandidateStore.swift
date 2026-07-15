import Combine
import Foundation

/// Persists candidates awaiting review so background-history processing can restore and
/// present every probable session in chronological order.
@MainActor
public final class DetectionCandidateStore: ObservableObject {
	@Published public private(set) var pendingCandidates: [DetectionCandidate] = []

	public var pendingCandidate: DetectionCandidate? { pendingCandidates.first }
	public var pendingCount: Int { pendingCandidates.count }

	private let userDefaults: UserDefaults
	private let storageKey: String

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionCandidateStore.pending.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		if let data = userDefaults.data(forKey: storageKey) {
			if let decoded = try? JSONDecoder().decode([DetectionCandidate].self, from: data) {
				pendingCandidates = decoded.sorted { $0.gestureAt < $1.gestureAt }
			} else if let legacyCandidate = try? JSONDecoder().decode(DetectionCandidate.self, from: data) {
				pendingCandidates = [legacyCandidate]
			}
		}
	}

	@discardableResult
	public func present(_ candidate: DetectionCandidate) -> Bool {
		guard pendingCandidates.contains(where: { $0.id == candidate.id }) == false else { return false }
		pendingCandidates.append(candidate)
		pendingCandidates.sort { $0.gestureAt < $1.gestureAt }
		persist()
		return true
	}

	@discardableResult
	public func resolve(candidateID: UUID) -> Bool {
		guard let index = pendingCandidates.firstIndex(where: { $0.id == candidateID }) else { return false }
		pendingCandidates.remove(at: index)
		persist()
		return true
	}

	private func persist() {
		guard pendingCandidates.isEmpty == false else {
			userDefaults.removeObject(forKey: storageKey)
			return
		}
		if let data = try? JSONEncoder().encode(pendingCandidates) {
			userDefaults.set(data, forKey: storageKey)
		}
	}
}
