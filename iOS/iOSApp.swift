import SwiftUI
import Combine
import CiggyShared

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
					appCoordinator.start(repository: repository, settings: settingsStore)
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
@MainActor
final class IOSAppCoordinator: ObservableObject {
	private var cancellables = Set<AnyCancellable>()
	private var hasStarted = false

	func start(repository: EventRepository, settings: UserSettingsStore) {
		guard hasStarted == false else { return }
		hasStarted = true

		ConnectivityManager.shared.incomingEvent
			.sink { @MainActor event in
				repository.addEvent(event)
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
			.sink { @MainActor sharedSettings in
				ConnectivityManager.shared.send(settings: sharedSettings)
			}
			.store(in: &cancellables)
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
		.tint(CiggyTheme.mint)
		.toolbarBackground(CiggyTheme.deepInk, for: .tabBar)
		.toolbarBackground(.visible, for: .tabBar)
	}
}
#else
@main
struct CiggyiOSHostPlaceholder {
	static func main() {}
}
#endif
