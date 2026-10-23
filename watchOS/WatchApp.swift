import SwiftUI
import Combine
import CiggyShared
#if os(watchOS)
import WatchKit

@main
struct CiggyWatchApp: App {
	@WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var runtime = WatchAppRuntime.shared

	var body: some Scene {
		WindowGroup {
			NavigationStack { WatchDashboardView() }
				.environmentObject(runtime.repository)
				.environmentObject(runtime.settingsStore)
				.environmentObject(runtime.reviewStore)
				.environmentObject(runtime.coordinator)
				.onAppear { runtime.start() }
				.onChange(of: scenePhase) { _, phase in
					switch phase {
					case .active:
						runtime.coordinator.appDidBecomeActive()
					case .background:
						runtime.coordinator.appDidEnterBackground()
					case .inactive:
						break
					@unknown default:
						break
					}
				}
				.tint(CiggyTheme.ember)
				.ciggyAppearance()
		}
	}
}

@MainActor
final class WatchAppRuntime: ObservableObject {
	static let shared = WatchAppRuntime()
	let repository = EventRepository()
	let settingsStore = UserSettingsStore()
	let reviewStore = DetectionReviewStore()
	let legacyCandidateStore = DetectionCandidateStore()
	let coordinator = WatchAppCoordinator()

	func start() {
		coordinator.start(repository: repository, settings: settingsStore, reviewStore: reviewStore,
		                  legacyCandidateStore: legacyCandidateStore)
	}
}

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
	private var runningTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

	func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
		// Background launches do not necessarily construct the dashboard. Bind the
		// same stores here before WatchConnectivity delivers queued events.
		WatchAppRuntime.shared.start()
		for task in backgroundTasks {
			guard task is WKApplicationRefreshBackgroundTask || task is WKWatchConnectivityRefreshBackgroundTask else {
				task.setTaskCompletedWithSnapshot(false)
				continue
			}
			let id = ObjectIdentifier(task)
			runningTasks[id] = Task { @MainActor [weak self] in
				BackgroundMotionMonitor.shared.armRecording()
				if task is WKApplicationRefreshBackgroundTask {
					BackgroundMotionMonitor.shared.backgroundRefreshDidBegin()
				} else {
					await ConnectivityManager.shared.drainPendingBackgroundTransfers(maximumWait: 1)
				}
				guard Task.isCancelled == false else { return }
				// Every legitimate wake is useful: a phone sync can renew capture
				// and check recent movement without opening the Watch interface.
				await WatchAppRuntime.shared.coordinator.refreshTracking()
				self?.complete(task)
			}
			task.expirationHandler = { [weak self] in
				Task { @MainActor [weak self] in self?.complete(task) }
			}
		}
	}

	private func complete(_ task: WKRefreshBackgroundTask) {
		guard let work = runningTasks.removeValue(forKey: ObjectIdentifier(task)) else { return }
		work.cancel()
		task.expirationHandler = nil
		task.setTaskCompletedWithSnapshot(false)
	}
}

@MainActor
final class WatchAppCoordinator: ObservableObject {
	private let detection = DetectionAlgorithm()
	private var notificationsEnabled = false
	private var hasStarted = false
	private var isForegroundMonitoring = false
	private var hasRequestedHealthAuthorization = false
	private var hasStartedDebugRecording = false
	private var isRequestingNotificationAuthorization = false
	private var historyRefresh: Task<Void, Never>?
	private var companionRefresh: Task<Void, Never>?
	private var trackingRefresh: Task<Void, Never>?
	private let lastRefreshRequestKey = "Ciggy.lastHandledHistoryRefreshRequest.v1"
	private let lastRefreshRequestAtKey = "Ciggy.lastHandledHistoryRefreshAt.v1"
	private weak var repository: EventRepository?
	private weak var settingsStore: UserSettingsStore?
	private weak var reviewStore: DetectionReviewStore?
	private var cancellables: Set<AnyCancellable> = []
	private let widgetSync = WidgetSyncCoordinator()

	func start(
		repository: EventRepository,
		settings: UserSettingsStore,
		reviewStore: DetectionReviewStore,
		legacyCandidateStore: DetectionCandidateStore
	) {
		guard hasStarted == false else { return }
		hasStarted = true
		widgetSync.bind(repository: repository, settings: settings)
		NotificationManager.configurePresentation()
		self.repository = repository
		settingsStore = settings
		self.reviewStore = reviewStore

		settings.$settings
			.removeDuplicates()
			.sink { @MainActor [weak self] sharedSettings in
				self?.notificationsEnabled = sharedSettings.notificationsEnabled
				self?.detection.updateSensitivity(multiplier: sharedSettings.sensitivity)
				self?.requestNotificationAuthorizationIfActive()
				if sharedSettings.calibrationEnabledAt == nil {
					Task { @MainActor in await BackgroundCalibrationCollector.shared.collect(enabledAt: nil) }
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
				reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
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
				reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
			}
			.store(in: &cancellables)

		ConnectivityManager.shared.incomingHistoryRefreshRequest
			.sink { @MainActor [weak self] request in
				guard let self, UserDefaults.standard.string(forKey: self.lastRefreshRequestKey) != request.id.uuidString else { return }
				if let handledAt = UserDefaults.standard.object(forKey: self.lastRefreshRequestAtKey) as? Date,
				   request.requestedAt <= handledAt { return }
				UserDefaults.standard.set(request.id.uuidString, forKey: self.lastRefreshRequestKey)
				UserDefaults.standard.set(request.requestedAt, forKey: self.lastRefreshRequestAtKey)
				guard self.companionRefresh == nil else { return }
				self.companionRefresh = Task { @MainActor [weak self] in
					await self?.refreshTracking()
					self?.companionRefresh = nil
				}
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

		reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
		let legacyCandidates = legacyCandidateStore.pendingCandidates
		ConnectivityManager.shared.activateIncomingDelivery()
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
		guard hasStarted else { return }
		ConnectivityManager.shared.resumeSync()
		BackgroundMotionMonitor.shared.armRecording()
		requestNotificationAuthorizationIfActive()
		#if DEBUG
		// Opt-in launch argument enables a physical-watch test without coupling the
		// sensor APIs to the UI being designed in the other chat.
		if hasStartedDebugRecording == false, ProcessInfo.processInfo.arguments.contains("-CiggyRecordMotion") {
			hasStartedDebugRecording = true
			MotionRecordingStore.shared.completedRecording
				.sink { @MainActor url in ConnectivityManager.shared.sendMotionRecording(at: url) }
				.store(in: &cancellables)
			MotionRecordingStore.shared.start(label: .unlabelled)
		}
		#endif
		// start() is idempotent while healthy and retries a failed sensor stream.
		MotionManager.shared.start()
		if isForegroundMonitoring == false {
			isForegroundMonitoring = true
			startHeartRateMonitoring()
		}

		guard historyRefresh == nil else { return }
		historyRefresh = Task { @MainActor [weak self] in
			while Task.isCancelled == false {
				MotionManager.shared.start()
				await self?.refreshTracking()
				do { try await Task.sleep(for: .seconds(60)) } catch { break }
			}
		}
	}

	func refreshTracking() async {
		guard hasStarted else { return }
		if let trackingRefresh { await trackingRefresh.value; return }
		let work = Task { @MainActor [weak self] in
			BackgroundMotionMonitor.shared.armRecording()
			await self?.processHistory()
			guard Task.isCancelled == false else { return }
			await BackgroundCalibrationCollector.shared.collect(
				enabledAt: self?.settingsStore?.settings.calibrationEnabledAt,
				maximumProcessingTime: WKApplication.shared().applicationState == .active ? 6 : 1
			)
			ConnectivityManager.shared.resumeSync()
		}
		trackingRefresh = work
		await withTaskCancellationHandler {
			await work.value
		} onCancel: {
			work.cancel()
		}
		trackingRefresh = nil
	}

	/// Used by both foreground catch-up and best-effort watchOS background refresh.
	func processHistory() async {
		guard hasStarted, let repository, let settingsStore, let reviewStore else { return }
		let backgroundMotion = BackgroundMotionMonitor.shared
		guard let batch = await backgroundMotion.processAvailableHistory(
			sensitivity: settingsStore.settings.sensitivity,
			maximumProcessingTime: WKApplication.shared().applicationState == .active ? 20 : 4
		), Task.isCancelled == false else { return }
		let reviews = autoRecord(
			batch.candidates, origin: .watchHistory,
			windowStart: batch.processedFrom, windowEnd: batch.processedThrough,
			repository: repository, reviewStore: reviewStore
		)
		if notificationsEnabled, let review = reviews.last(where: { Calendar.current.isDate($0.windowEnd, inSameDayAs: Date()) }) {
			NotificationManager.scheduleDetectionSummaryNotification(
				reviewID: review.id, count: review.eventIDs.count, historyHours: review.historyHours
			)
		}
		backgroundMotion.commit(batch)
		ConnectivityManager.shared.resumeSync()
	}

	func appDidEnterBackground() {
		guard hasStarted else { return }
		BackgroundMotionMonitor.shared.armRecording()
		historyRefresh?.cancel()
		historyRefresh = nil
		MotionManager.shared.stop()
		// Preserve completed puffs across a short screen sleep. The fusion engine
		// expires long gaps itself; an incomplete sensor gesture still resets.
		HealthKitManager.shared.stopHeartRateStreaming()
		isForegroundMonitoring = false
	}

	private func requestNotificationAuthorizationIfActive() {
		guard notificationsEnabled, isRequestingNotificationAuthorization == false,
		      WKApplication.shared().applicationState == .active, let settingsStore else { return }
		isRequestingNotificationAuthorization = true
		Task { @MainActor [weak self] in
			let granted = await NotificationManager.requestAuthorization()
			guard let self else { return }
			self.isRequestingNotificationAuthorization = false
			if granted == false, settingsStore.settings.notificationsEnabled {
				self.notificationsEnabled = false
				settingsStore.settings.notificationsEnabled = false
				ConnectivityManager.shared.send(settings: settingsStore.settings)
			}
		}
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
	) -> [DetectionReview] {
		var newEvents: [SmokingEvent] = []
		var reviewStart = windowStart
		var reviewEnd = windowEnd
		for candidate in candidates {
			let event = candidate.detectedEvent()
			// The repository compares supporting motion intervals across live/history
			// and retains corrected sessions without an eight-minute blanket block.
			guard repository.addEvent(event) else { continue }
			newEvents.append(event)
			reviewStart = min(reviewStart, candidate.motionSessionStartedAt ?? candidate.gestureAt)
			reviewEnd = max(reviewEnd, candidate.gestureAt)
			ConnectivityManager.shared.send(event: event)
		}
		let reviews = reviewStore.recordDaily(
			events: newEvents, origin: origin, windowStart: reviewStart, windowEnd: reviewEnd
		)
		reviews.forEach { ConnectivityManager.shared.send(review: $0) }
		return reviews
	}
}
#else
@main
struct CiggyWatchHostPlaceholder {
	static func main() {}
}
#endif
