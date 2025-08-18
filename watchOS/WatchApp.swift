import SwiftUI
import Combine

#if os(watchOS)
@main
struct CiggyWatchApp: App {
	@StateObject private var repository = EventRepository()
	@StateObject private var settingsStore = UserSettingsStore()
	@StateObject private var watchCoordinator = WatchAppCoordinator()

	var body: some Scene {
		WindowGroup {
			NavigationView { WatchDashboardView() }
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.onAppear {
					watchCoordinator.start(repository: repository, settings: settingsStore)
				}
		}
	}
}

final class WatchAppCoordinator: ObservableObject {
	private let detection = DetectionAlgorithm()

	func start(repository: EventRepository, settings: UserSettingsStore) {
		// Start motion and HR streaming
		MotionManager.shared.start()
		Task { await HealthKitManager.shared.requestAuthorization(); HealthKitManager.shared.startHeartRateStreaming() }
		// Sensitivity binding
		detection.updateSensitivity(multiplier: settings.settings.sensitivity)
		// Incoming confirmed events
		detection.eventPublisher
			.receive(on: DispatchQueue.main)
			.sink { event in
				repository.addEvent(event)
				NotificationManager.scheduleDetectionNotification(heartRate: event.heartRate)
				ConnectivityManager.shared.send(event: event)
			}
			.store(in: &cancellables)
	}

	private var cancellables: Set<AnyCancellable> = []
}
#endif


