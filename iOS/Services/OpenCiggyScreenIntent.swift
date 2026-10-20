#if os(iOS)
import AppIntents
import CiggyShared
import Foundation

// Compile directly into both the app and widget extension. Keeping the OpenIntent
// and its AppEnum only in a package can break control metadata resolution.
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

#endif
