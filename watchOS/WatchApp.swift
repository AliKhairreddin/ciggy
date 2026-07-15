import SwiftUI
import Combine
import CiggyShared
#if os(watchOS)
import WatchKit

@main
struct CiggyWatchApp: App {
	@WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var repository = EventRepository()
	@StateObject private var settingsStore = UserSettingsStore()
	@StateObject private var feedbackStore = DetectionFeedbackStore()
	@StateObject private var candidateStore = DetectionCandidateStore()
	@StateObject private var watchCoordinator = WatchAppCoordinator()

	var body: some Scene {
		WindowGroup {
			NavigationStack { WatchDashboardView() }
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.environmentObject(feedbackStore)
				.environmentObject(candidateStore)
				.environmentObject(watchCoordinator)
				.onAppear {
					watchCoordinator.start(settings: settingsStore, candidateStore: candidateStore)
				}
				.onChange(of: scenePhase) { _, phase in
					switch phase {
					case .active:
						watchCoordinator.appDidBecomeActive()
					case .background:
						watchCoordinator.appDidEnterBackground()
					case .inactive:
						break
					@unknown default:
						break
					}
				}
				.tint(CiggyTheme.mint)
		}
	}
}

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
	func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
		for task in backgroundTasks {
			if task is WKApplicationRefreshBackgroundTask {
				BackgroundMotionMonitor.shared.armRecording()
			}
			task.setTaskCompletedWithSnapshot(false)
		}
	}
}

@MainActor
final class WatchAppCoordinator: ObservableObject {
	private let detection = DetectionAlgorithm()
	private var notificationsEnabled = false
	private var hasStarted = false
	private var isForegroundMonitoring = false
	private var hasRequestedHealthAuthorization = false
	private weak var settingsStore: UserSettingsStore?
	private weak var candidateStore: DetectionCandidateStore?
	private var cancellables: Set<AnyCancellable> = []

	func start(settings: UserSettingsStore, candidateStore: DetectionCandidateStore) {
		guard hasStarted == false else { return }
		hasStarted = true
		settingsStore = settings
		self.candidateStore = candidateStore

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
				self?.present(candidate, candidateStore: candidateStore, schedulesNotification: true)
			}
			.store(in: &cancellables)

		if WKApplication.shared().applicationState == .active {
			appDidBecomeActive()
		}
	}

	func appDidBecomeActive() {
		guard hasStarted, let settingsStore, let candidateStore else { return }
		if isForegroundMonitoring == false {
			isForegroundMonitoring = true
			MotionManager.shared.start()
			startHeartRateMonitoring()
		}

		let backgroundMotion = BackgroundMotionMonitor.shared
		backgroundMotion.armRecording()
		Task { @MainActor [weak self, weak candidateStore] in
			guard let self, let candidateStore else { return }
			guard let batch = await backgroundMotion.processAvailableHistory(
				sensitivity: settingsStore.settings.sensitivity
			) else { return }
			for candidate in batch.candidates {
				self.present(candidate, candidateStore: candidateStore, schedulesNotification: false)
			}
			backgroundMotion.commit(batch)
		}
	}

	func appDidEnterBackground() {
		guard hasStarted else { return }
		BackgroundMotionMonitor.shared.markForegroundProcessed()
		BackgroundMotionMonitor.shared.armRecording()
		MotionManager.shared.stop()
		HealthKitManager.shared.stopHeartRateStreaming()
		isForegroundMonitoring = false
	}

	private func startHeartRateMonitoring() {
		if hasRequestedHealthAuthorization {
			HealthKitManager.shared.startHeartRateStreaming()
			return
		}
		hasRequestedHealthAuthorization = true
		Task { @MainActor [weak self] in
			await HealthKitManager.shared.requestAuthorization()
			guard self?.isForegroundMonitoring == true else { return }
			HealthKitManager.shared.startHeartRateStreaming()
		}
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

	private func present(
		_ candidate: DetectionCandidate,
		candidateStore: DetectionCandidateStore,
		schedulesNotification: Bool
	) {
		guard candidateStore.present(candidate) else { return }
		if notificationsEnabled && schedulesNotification {
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
