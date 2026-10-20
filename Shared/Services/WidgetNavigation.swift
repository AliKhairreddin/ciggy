#if os(iOS)
import Foundation

/// Foreground control intents open the app's existing flow without silently logging an event.
public enum WidgetNavigation {
	public static let requested = Notification.Name("Ciggy.widgetNavigation")
	private static let key = "Ciggy.widgets.pendingDestination"

	@MainActor public static func open(_ destination: String) {
		UserDefaults(suiteName: WidgetSnapshotStore.appGroup)?.set(destination, forKey: key)
		NotificationCenter.default.post(name: requested, object: nil)
	}

	public static func consume() -> String? {
		let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup)
		let destination = defaults?.string(forKey: key)
		defaults?.removeObject(forKey: key)
		return destination
	}
}

#endif
