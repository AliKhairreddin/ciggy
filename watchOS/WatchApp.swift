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
	@StateObject private var reviewStore = DetectionReviewStore()
	@StateObject private var legacyCandidateStore = DetectionCandidateStore()
	@StateObject private var watchCoordinator = WatchAppCoordinator()

	var body: some Scene {
		WindowGroup {
			NavigationStack { WatchDashboardView() }
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.environmentObject(reviewStore)
				.environmentObject(watchCoordinator)
				.onAppear {
					watchCoordinator.start(
						repository: repository,
						settings: settingsStore,
						reviewStore: reviewStore,
						legacyCandidateStore: legacyCandidateStore
					)
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
	private weak var repository: EventRepository?
	private weak var settingsStore: UserSettingsStore?
	private weak var reviewStore: DetectionReviewStore?
	private var cancellables: Set<AnyCancellable> = []

	func start(
		repository: EventRepository,
		settings: UserSettingsStore,
		reviewStore: DetectionReviewStore,
		legacyCandidateStore: DetectionCandidateStore
	) {
		guard hasStarted == false else { return }
		hasStarted = true
		self.repository = repository
		settingsStore = settings
		self.reviewStore = reviewStore

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

		ConnectivityManager.shared.incomingEvent
			.sink { @MainActor event in
				repository.addEvent(event)
			}
			.store(in: &cancellables)

		ConnectivityManager.shared.incomingDeletedEventID
			.sink { @MainActor eventID in
				repository.removeEvent(id: eventID)
			}
			.store(in: &cancellables)

		ConnectivityManager.shared.incomingReview
			.sink { @MainActor review in
				reviewStore.upsert(review)
			}
			.store(in: &cancellables)

		detection.candidatePublisher
			.sink { @MainActor [weak self] candidate in
				self?.autoRecord(
					[candidate],
					origin: .liveWatch,
					windowStart: candidate.motionSessionStartedAt ?? candidate.gestureAt,
					windowEnd: candidate.gestureAt,
					repository: repository,
					reviewStore: reviewStore
				)
			}
			.store(in: &cancellables)

		let legacyCandidates = legacyCandidateStore.pendingCandidates
		if let first = legacyCandidates.first, let last = legacyCandidates.last {
			autoRecord(
				legacyCandidates,
				origin: .watchHistory,
				windowStart: first.motionSessionStartedAt ?? first.gestureAt,
				windowEnd: last.gestureAt,
				repository: repository,
				reviewStore: reviewStore
			)
			legacyCandidates.forEach { legacyCandidateStore.resolve(candidateID: $0.id) }
		}

		if WKApplication.shared().applicationState == .active {
			appDidBecomeActive()
		}
	}

	func appDidBecomeActive() {
		guard hasStarted, let repository, let settingsStore, let reviewStore else { return }
		if isForegroundMonitoring == false {
			isForegroundMonitoring = true
			MotionManager.shared.start()
			startHeartRateMonitoring()
		}

		let backgroundMotion = BackgroundMotionMonitor.shared
		backgroundMotion.armRecording()
		Task { @MainActor [weak self, weak repository, weak reviewStore] in
			guard let self, let repository, let reviewStore else { return }
			guard let batch = await backgroundMotion.processAvailableHistory(
				sensitivity: settingsStore.settings.sensitivity
			) else { return }
			if let review = self.autoRecord(
				batch.candidates,
				origin: .watchHistory,
				windowStart: batch.processedFrom,
				windowEnd: batch.processedThrough,
				repository: repository,
				reviewStore: reviewStore
			), self.notificationsEnabled {
				NotificationManager.scheduleDetectionSummaryNotification(
					reviewID: review.id,
					count: batch.candidates.count,
					historyHours: max(
						1,
						Int(ceil(batch.processedThrough.timeIntervalSince(batch.processedFrom) / 3_600))
					)
				)
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

	@discardableResult
	private func autoRecord(
		_ candidates: [DetectionCandidate],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		repository: EventRepository,
		reviewStore: DetectionReviewStore
	) -> DetectionReview? {
		var newEvents: [SmokingEvent] = []
		for candidate in candidates {
			let event = candidate.detectedEvent()
			guard repository.addEvent(event) else { continue }
			newEvents.append(event)
			ConnectivityManager.shared.send(event: event)
		}
		guard let review = reviewStore.record(
			events: newEvents,
			origin: origin,
			windowStart: windowStart,
			windowEnd: windowEnd
		) else { return nil }
		ConnectivityManager.shared.send(review: review)
		return review
	}
}
#else
@main
struct CiggyWatchHostPlaceholder {
	static func main() {}
}
#endif
