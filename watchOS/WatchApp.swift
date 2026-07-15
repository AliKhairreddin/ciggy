import SwiftUI
import Combine
import CiggyShared
#if os(watchOS)
import WatchKit

@main
struct CiggyWatchApp: App {
	@StateObject private var repository = EventRepository()
	@StateObject private var settingsStore = UserSettingsStore()
	@StateObject private var feedbackStore = DetectionFeedbackStore()
	@StateObject private var candidateStore = DetectionCandidateStore()
	@StateObject private var watchCoordinator = WatchAppCoordinator()

	var body: some Scene {
		WindowGroup {
			NavigationView { WatchDashboardView() }
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.environmentObject(feedbackStore)
				.environmentObject(candidateStore)
				.environmentObject(watchCoordinator)
				.onAppear {
					watchCoordinator.start(settings: settingsStore, candidateStore: candidateStore)
				}
		}
	}
}

@MainActor
final class WatchAppCoordinator: ObservableObject {
	private let detection = DetectionAlgorithm()
	private var notificationsEnabled = false
	private var hasStarted = false
	private var cancellables: Set<AnyCancellable> = []

	func start(settings: UserSettingsStore, candidateStore: DetectionCandidateStore) {
		guard hasStarted == false else { return }
		hasStarted = true

		MotionManager.shared.start()
		Task { @MainActor in
			await HealthKitManager.shared.requestAuthorization()
			HealthKitManager.shared.startHeartRateStreaming()
		}

		settings.$settings
			.removeDuplicates()
			.sink { @MainActor [weak self] sharedSettings in
				let shouldRequestNotifications = sharedSettings.notificationsEnabled && self?.notificationsEnabled == false
				self?.notificationsEnabled = sharedSettings.notificationsEnabled
				self?.detection.updateSensitivity(multiplier: sharedSettings.sensitivity)
				if shouldRequestNotifications {
					Task { @MainActor [weak self] in
						let granted = await NotificationManager.requestAuthorization()
						if granted == false, settings.settings.notificationsEnabled {
							self?.notificationsEnabled = false
							settings.settings.notificationsEnabled = false
							ConnectivityManager.shared.send(settings: settings.settings)
						}
					}
				}
			}
			.store(in: &cancellables)

		ConnectivityManager.shared.incomingSettings
			.sink { @MainActor remoteSettings in
				guard let remoteSettings else { return }
				guard settings.settings != remoteSettings else { return }
				settings.settings = remoteSettings
			}
			.store(in: &cancellables)

		detection.candidatePublisher
			.sink { @MainActor [weak self] candidate in
				self?.present(candidate, candidateStore: candidateStore)
			}
			.store(in: &cancellables)
	}

	func confirm(
		_ candidate: DetectionCandidate,
		repository: EventRepository,
		feedbackStore: DetectionFeedbackStore,
		candidateStore: DetectionCandidateStore
	) {
		guard candidateStore.pendingCandidate?.id == candidate.id else { return }
		let event = candidate.confirmedEvent()
		repository.addEvent(event)
		feedbackStore.record(candidate: candidate, decision: .confirmed)
		ConnectivityManager.shared.send(event: event)
		NotificationManager.removeDetectionCandidateNotification(candidateID: candidate.id)
		candidateStore.resolve(candidateID: candidate.id)
		WKInterfaceDevice.current().play(.success)
	}

	func dismiss(
		_ candidate: DetectionCandidate,
		feedbackStore: DetectionFeedbackStore,
		candidateStore: DetectionCandidateStore
	) {
		guard candidateStore.pendingCandidate?.id == candidate.id else { return }
		feedbackStore.record(candidate: candidate, decision: .dismissed)
		NotificationManager.removeDetectionCandidateNotification(candidateID: candidate.id)
		candidateStore.resolve(candidateID: candidate.id)
		WKInterfaceDevice.current().play(.click)
	}

	private func present(_ candidate: DetectionCandidate, candidateStore: DetectionCandidateStore) {
		guard candidateStore.present(candidate) else { return }
		if notificationsEnabled {
			NotificationManager.scheduleDetectionCandidateNotification(candidateID: candidate.id)
		}
	}
}
#else
@main
struct CiggyWatchHostPlaceholder {
	static func main() {}
}
#endif
