import SwiftUI
import Combine

#if os(iOS)
@main
struct CiggyiOSApp: App {
	@StateObject private var repository = EventRepository()
	@StateObject private var settingsStore = UserSettingsStore()
	@StateObject private var appCoordinator = IOSAppCoordinator()

	var body: some Scene {
		WindowGroup {
			RootTabView()
				.environmentObject(repository)
				.environmentObject(settingsStore)
				.onAppear {
					Task { _ = await NotificationManager.requestAuthorization() }
					appCoordinator.start(repository: repository)
					// Apply sensitivity to detection algorithm if used on iOS later
					// Seed a baseline for money-saved estimate if not set
					if UserDefaults.standard.integer(forKey: "baselineCigsPerDay") == 0 {
						UserDefaults.standard.set(settingsStore.settings.dailyLimit, forKey: "baselineCigsPerDay")
					}
				}
		}
	}
}

/// Coordinates incoming connectivity events on iOS
final class IOSAppCoordinator: ObservableObject {
	private var cancellables = Set<AnyCancellable>()

	func start(repository: EventRepository) {
		ConnectivityManager.shared.incomingEvent
			.receive(on: DispatchQueue.main)
			.sink { event in
				repository.addEvent(event)
			}
			.store(in: &cancellables)
	}
}

/// Root TabView with Dashboard, Reports, Goals, Settings
struct RootTabView: View {
	var body: some View {
		TabView {
			DashboardView()
				.tabItem { Label("Dashboard", systemImage: "house.fill") }

			ReportsView()
				.tabItem { Label("Reports", systemImage: "chart.bar.fill") }

			GoalsView()
				.tabItem { Label("Goals", systemImage: "target") }

			SettingsView()
				.tabItem { Label("Settings", systemImage: "gearshape.fill") }
		}
	}
}
#endif


