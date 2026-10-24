import SwiftUI
import Combine
import CiggyShared

#if os(iOS)
@main
struct CiggyiOSApp: App {
	@UIApplicationDelegateAdaptor private var appDelegate: IOSAppDelegate
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var runtime = IOSAppRuntime.shared
	@StateObject private var liveActivity = LiveActivityManager()

	var body: some Scene {
		WindowGroup {
			RootTabView()
				.environmentObject(runtime.repository)
				.environmentObject(runtime.settingsStore)
				.environmentObject(runtime.reviewStore)
				.environmentObject(liveActivity)
				.onAppear {
					liveActivity.bind(repository: runtime.repository, settings: runtime.settingsStore)
					runtime.start()
					runtime.coordinator.refreshNotifications()
					// Seed a baseline for money-saved estimate if not set
					if UserDefaults.standard.integer(forKey: "baselineCigsPerDay") == 0 {
						UserDefaults.standard.set(runtime.settingsStore.settings.dailyLimit, forKey: "baselineCigsPerDay")
					}
				}
				.onChange(of: scenePhase) { _, phase in
					if phase == .active {
						ConnectivityManager.shared.resumeSync()
						CalibrationUploadManager.shared.flush()
						runtime.coordinator.refreshNotifications()
						ConnectivityManager.shared.requestHistoryRefresh()
						liveActivity.refresh()
					}
				}
		}
	}
}

/// WatchConnectivity can launch the companion without creating a visible scene.
/// Bind repositories once for both background delivery and foreground presentation.
@MainActor
final class IOSAppRuntime: ObservableObject {
	static let shared = IOSAppRuntime()
	let repository = EventRepository()
	let settingsStore = UserSettingsStore()
	let reviewStore = DetectionReviewStore()
	let coordinator = IOSAppCoordinator()

	func start() {
		coordinator.start(repository: repository, settings: settingsStore, reviewStore: reviewStore)
	}
}

@MainActor
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
		CalibrationBackgroundDelivery.shared.register()
		IOSAppRuntime.shared.start()
		return true
	}

	func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
	                 completionHandler: @escaping () -> Void) {
		guard identifier == CalibrationUploadManager.sessionIdentifier else { completionHandler(); return }
		CalibrationUploadManager.shared.restoreBackgroundSession(completion: completionHandler)
		IOSAppRuntime.shared.start()
	}
}

/// Coordinates incoming connectivity events on iOS
@MainActor
final class IOSAppCoordinator: ObservableObject {
	private var cancellables = Set<AnyCancellable>()
	private var hasStarted = false
	private let widgetSync = WidgetSyncCoordinator()
	private var notificationsEnabled = false
	private let roastPlanner = DailyRoastPlanner()
	private let notificationRefresh = PassthroughSubject<Void, Never>()
	private var dailyLimit = 10
	private var lastNotificationCount = 0
	private weak var settingsStore: UserSettingsStore?
	private var isRequestingNotificationAuthorization = false

	func refreshNotifications() {
		requestNotificationAuthorizationIfActive()
		notificationRefresh.send(())
	}

	private func requestNotificationAuthorizationIfActive() {
		guard notificationsEnabled, isRequestingNotificationAuthorization == false,
		      UIApplication.shared.applicationState == .active, let settingsStore else { return }
		isRequestingNotificationAuthorization = true
		Task { @MainActor [weak self] in
			let granted = await NotificationManager.requestAuthorization()
			guard let self else { return }
			self.isRequestingNotificationAuthorization = false
			if granted == false, settingsStore.settings.notificationsEnabled {
				settingsStore.settings.notificationsEnabled = false
			}
		}
	}

	func start(
		repository: EventRepository,
		settings: UserSettingsStore,
		reviewStore: DetectionReviewStore
	) {
		guard hasStarted == false else { return }
		hasStarted = true
		CalibrationUploadManager.shared.bind(settings: settings)
		settingsStore = settings
		widgetSync.bind(repository: repository, settings: settings)
		NotificationManager.configurePresentation()
		// Existing history is a baseline, not a reason to alert on every launch.
		lastNotificationCount = repository.dailyCount(on: Date())
		_ = roastPlanner.next(count: lastNotificationCount, dailyLimit: settings.settings.dailyLimit, enabled: false)

		// Coalesce historical batches and live/queued sync into one current-count roast.
		// iPhone owns these alerts; the system can route them to its paired Watch.
		repository.$events
			.handleEvents(receiveOutput: { @MainActor [weak self] events in
				guard let self else { return }
				let now = Date()
				let count = events.filter { $0.timestamp <= now && Calendar.current.isDate($0.timestamp, inSameDayAs: now) }.count
				// Undo cancels a queued alert immediately, before the debounce window.
				if count < self.lastNotificationCount { NotificationManager.cancelPendingDailyRoasts() }
				self.lastNotificationCount = count
			})
			.combineLatest(notificationRefresh.prepend(()))
			.debounce(for: .seconds(2), scheduler: RunLoop.main)
			.sink { @MainActor [weak self] events, _ in
				let now = Date()
				let count = events.filter { $0.timestamp <= now && Calendar.current.isDate($0.timestamp, inSameDayAs: now) }.count
				guard let self else { return }
				if let roast = self.roastPlanner.next(count: count, dailyLimit: self.dailyLimit, enabled: self.notificationsEnabled, at: now) {
					NotificationManager.scheduleDailyRoast(roast)
				}
				if let recap = self.roastPlanner.recap(events: events, dailyLimit: self.dailyLimit, enabled: self.notificationsEnabled, at: now) {
					NotificationManager.scheduleDailyRoast(recap, recap: true)
				}
			}
			.store(in: &cancellables)

		repository.configureEventDelivery(
			enqueueEvent: { ConnectivityManager.shared.send(event: $0) },
			enqueueDeletion: { ConnectivityManager.shared.sendDeletedEvent(id: $0) }
		)
		reviewStore.configureCorrectionDelivery(repository: repository, enqueue: { ConnectivityManager.shared.send(review: $0) })
		ConnectivityManager.shared.bindMutationReceivers(
			event: { event in
				guard repository.receiveEvent(event) else { return false }
				guard reviewStore.retryPendingCorrections() else { return false }
				reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
				return reviewStore.lastPersistenceError == nil
			},
			deletion: { repository.receiveDeletion(id: $0) },
			review: { review in
				guard reviewStore.receive(review) else { return false }
				reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
				return reviewStore.lastPersistenceError == nil
			},
			retry: {
				_ = repository.retryPendingEventMutations()
				_ = reviewStore.retryPendingCorrections()
			}
		)

		ConnectivityManager.shared.incomingSettings
			.sink { @MainActor remoteSettings in
				guard let remoteSettings else { return }
				guard settings.settings != remoteSettings else { return }
				settings.settings = remoteSettings
			}
			.store(in: &cancellables)

		settings.$settings
			.removeDuplicates()
			.sink { @MainActor [weak self] sharedSettings in
				self?.notificationsEnabled = sharedSettings.notificationsEnabled
				self?.dailyLimit = sharedSettings.dailyLimit
				if sharedSettings.notificationsEnabled == false {
					NotificationManager.cancelPendingDailyRoasts()
				}
				self?.requestNotificationAuthorizationIfActive()
				ConnectivityManager.shared.send(settings: sharedSettings)
			}
			.store(in: &cancellables)
		reviewStore.normalizePendingReviews(events: repository.events).forEach { ConnectivityManager.shared.send(review: $0) }
		ConnectivityManager.shared.activateIncomingDelivery()
		if UIApplication.shared.applicationState == .active { ConnectivityManager.shared.requestHistoryRefresh() }
	}
}

/// Primary destinations. Settings is available from the dashboard profile.
struct RootTabView: View {
	@Environment(\.scenePhase) private var scenePhase
	@State private var selectedTab = 0
	@State private var todayPath = NavigationPath()
	@State private var isLogging = false

	var body: some View {
		TabView(selection: $selectedTab) {
			NavigationStack(path: $todayPath) { DashboardView() }
				.tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }
				.tag(0)

			NavigationStack { ReportsView() }
				.tabItem { Label("Reports", systemImage: "chart.bar.fill") }
				.tag(1)

			NavigationStack { GoalsView() }
				.tabItem { Label("Goals", systemImage: "target") }
				.tag(2)
		}
		.tint(CiggyTheme.ember)
		.ciggyAppearance()
		.onOpenURL { url in
			guard url.scheme == "ciggy" else { return }
			openDestination(url.host)
		}
		.onAppear { openDestination(WidgetNavigation.consume()) }
		.onChange(of: scenePhase) { _, phase in
			if phase == .active { openDestination(WidgetNavigation.consume()) }
		}
		.onReceive(NotificationCenter.default.publisher(for: WidgetNavigation.requested)) { _ in
			openDestination(WidgetNavigation.consume())
		}
		.sheet(isPresented: $isLogging) {
			PhoneLogSmokeView { event in
				NotificationCenter.default.post(name: Notification.Name("Ciggy.widgetLogSaved"), object: event)
			}
				.presentationDetents([.medium, .large])
				.presentationDragIndicator(.visible)
		}
	}

	private func openDestination(_ destination: String?) {
		switch destination {
		case "log": todayPath = NavigationPath(); selectedTab = 0; isLogging = true
		case "reports": selectedTab = 1
		case "goals": selectedTab = 2
		case "today": todayPath = NavigationPath(); selectedTab = 0
		default: break
		}
	}
}
#else
@main
struct CiggyiOSHostPlaceholder {
	static func main() {}
}
#endif
