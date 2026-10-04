import Foundation
#if (os(iOS) || os(watchOS)) && canImport(WidgetKit)
import Combine
import WidgetKit
#endif

public struct WidgetSnapshotStore {
	public static let appGroup = "group.That-Canadian-Software-Services.ciggy"
	private let defaults: UserDefaults?
	private let key = "Ciggy.widgets.snapshot.v1"

	public init(defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroup)) {
		self.defaults = defaults
	}

	public func read() -> WidgetSnapshot? {
		guard let data = defaults?.data(forKey: key) else { return nil }
		return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
	}

	@discardableResult
	public func write(_ snapshot: WidgetSnapshot) -> Bool {
		guard let defaults, read() != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return false }
		defaults.set(data, forKey: key)
		return true
	}
}

#if (os(iOS) || os(watchOS)) && canImport(WidgetKit)
/// Each device publishes from its own repository after existing WatchConnectivity delivery.
@MainActor
public final class WidgetSyncCoordinator {
	private var cancellables = Set<AnyCancellable>()
	private let store = WidgetSnapshotStore()

	public init() {}

	public func bind(repository: EventRepository, settings: UserSettingsStore) {
		guard cancellables.isEmpty else { return }
		repository.$events.combineLatest(settings.$settings)
			.sink { [weak self] events, settings in
				guard let self else { return }
				if self.store.write(WidgetSnapshot(events: events, dailyLimit: settings.dailyLimit)) {
					WidgetCenter.shared.reloadAllTimelines()
				}
			}
			.store(in: &cancellables)
	}
}
#endif
