import Combine
import Foundation

/// Persists confirmation and dismissal feedback for later detector tuning.
@MainActor
public final class DetectionFeedbackStore: ObservableObject {
	@Published public private(set) var feedback: [DetectionFeedback] = []

	private let userDefaults: UserDefaults
	private let storageKey: String

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionFeedbackStore.feedback.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		load()
	}

	public func record(
		candidate: DetectionCandidate,
		decision: DetectionFeedbackDecision,
		decidedAt: Date = Date()
	) {
		guard feedback.contains(where: { $0.candidate.id == candidate.id }) == false else { return }
		feedback.append(DetectionFeedback(candidate: candidate, decision: decision, decidedAt: decidedAt))
		feedback.sort { $0.decidedAt < $1.decidedAt }
		save()
	}

	public func removeAll() {
		feedback.removeAll()
		save()
	}

	private func load() {
		guard let data = userDefaults.data(forKey: storageKey),
		      let decoded = try? JSONDecoder().decode([DetectionFeedback].self, from: data) else {
			feedback = []
			return
		}
		feedback = decoded.sorted { $0.decidedAt < $1.decidedAt }
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(feedback) else { return }
		userDefaults.set(data, forKey: storageKey)
	}
}
