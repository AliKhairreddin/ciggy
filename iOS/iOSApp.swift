import SwiftUI
import Combine
import CiggyShared

#if os(iOS)
@main
struct CiggyiOSApp: App {
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var repository = EventRepository()
	@StateObject private var settingsStore = UserSettingsStore()
	@StateObject private var reviewStore = DetectionReviewStore()
	@StateObject private var appCoordinator = IOSAppCoordinator()

	var body: some Scene {
		WindowGroup {
			RootTabView()
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.environmentObject(reviewStore)
				.onAppear {
					appCoordinator.start(
						repository: repository,
						settings: settingsStore,
						reviewStore: reviewStore
					)
					// Apply sensitivity to detection algorithm if used on iOS later
					// Seed a baseline for money-saved estimate if not set
					if UserDefaults.standard.integer(forKey: "baselineCigsPerDay") == 0 {
						UserDefaults.standard.set(settingsStore.settings.dailyLimit, forKey: "baselineCigsPerDay")
					}
				}
				.onChange(of: scenePhase) { _, phase in
					if phase == .active {
						ConnectivityManager.shared.resumeSync()
						appCoordinator.refreshNotifications()
					}
				}
		}
	}
}

/// Coordinates incoming connectivity events on iOS
@MainActor
final class IOSAppCoordinator: ObservableObject {
	private var cancellables = Set<AnyCancellable>()
	private var hasStarted = false
	private var notificationsEnabled = false
	private let roastPlanner = DailyRoastPlanner()
	private let notificationRefresh = PassthroughSubject<Void, Never>()
	private var dailyLimit = 10
	private var lastNotificationCount = 0

	func refreshNotifications() {
		notificationRefresh.send(())
	}

	func start(
		repository: EventRepository,
		settings: UserSettingsStore,
		reviewStore: DetectionReviewStore
	) {
		guard hasStarted == false else { return }
		hasStarted = true
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
				let count = events.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }.count
				// Undo cancels a queued alert immediately, before the debounce window.
				if count < self.lastNotificationCount { NotificationManager.cancelPendingDailyRoasts() }
				self.lastNotificationCount = count
			})
			.combineLatest(notificationRefresh.prepend(()))
			.debounce(for: .seconds(2), scheduler: RunLoop.main)
			.sink { @MainActor [weak self] events, _ in
				let now = Date()
				let count = events.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }.count
				guard let self else { return }
				if let roast = self.roastPlanner.next(count: count, dailyLimit: self.dailyLimit, enabled: self.notificationsEnabled, at: now) {
					NotificationManager.scheduleDailyRoast(roast)
				}
				if let recap = self.roastPlanner.recap(events: events, dailyLimit: self.dailyLimit, enabled: self.notificationsEnabled, at: now) {
					NotificationManager.scheduleDailyRoast(recap, recap: true)
				}
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
				let shouldRequest = sharedSettings.notificationsEnabled && self?.notificationsEnabled == false
				self?.notificationsEnabled = sharedSettings.notificationsEnabled
				self?.dailyLimit = sharedSettings.dailyLimit
				if sharedSettings.notificationsEnabled == false {
					NotificationManager.cancelPendingDailyRoasts()
				}
				if shouldRequest {
					Task { @MainActor in
						let granted = await NotificationManager.requestAuthorization()
						if granted == false, settings.settings.notificationsEnabled {
							settings.settings.notificationsEnabled = false
						}
					}
				}
				ConnectivityManager.shared.send(settings: sharedSettings)
			}
			.store(in: &cancellables)
		ConnectivityManager.shared.activateIncomingDelivery()
	}
}

/// Root TabView with Dashboard, Reports, Goals, Settings
struct RootTabView: View {
	var body: some View {
		TabView {
			NavigationStack { DashboardView() }
				.tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }

			NavigationStack { ReportsView() }
				.tabItem { Label("Reports", systemImage: "chart.bar.fill") }

			NavigationStack { GoalsView() }
				.tabItem { Label("Goals", systemImage: "target") }

			NavigationStack { SettingsView() }
				.tabItem { Label("Settings", systemImage: "gearshape.fill") }
		}
		.tint(CiggyTheme.ember)
		.ciggyAppearance()
	}
}
#else
@main
struct CiggyiOSHostPlaceholder {
	static func main() {}
}
#endif
