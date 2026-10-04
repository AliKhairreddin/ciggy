#if os(iOS)
import AppIntents
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

@available(iOS 18.0, *)
public enum CiggyScreen: String, AppEnum {
	case log, today, reports
	public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ciggy screen")
	public static let caseDisplayRepresentations: [CiggyScreen: DisplayRepresentation] = [
		.log: "Log a cigarette", .today: "Today", .reports: "Reports"
	]
}

@available(iOS 18.0, *)
public struct OpenCiggyScreenIntent: OpenIntent {
	public static let title: LocalizedStringResource = "Open Ciggy"
	@Parameter(title: "Screen") public var target: CiggyScreen
	public init() {}
	public init(target: CiggyScreen) { self.target = target }
	@MainActor public func perform() async throws -> some IntentResult {
		WidgetNavigation.open(target.rawValue)
		return .result()
	}
}

public struct CiggySharedIntentsPackage: AppIntentsPackage {
	public init() {}
}
#endif
