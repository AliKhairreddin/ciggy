import AppIntents
import CiggyShared
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct CiggyLogControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyLogControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .log)) {
				Label("Log a cigarette", systemImage: "plus.circle.fill")
			}
		}.displayName("Quick Log").description("Open Ciggy to log a cigarette.")
	}
}

@available(iOS 18.0, *)
struct CiggyReportsControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyReportsControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .reports)) {
				Label("Reports", systemImage: "chart.bar.fill")
			}
		}.displayName("Ciggy Reports").description("Open your trends and reports.")
	}
}

@available(iOS 18.0, *)
struct CiggyTodayControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyTodayControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .today)) {
				Label("Today", systemImage: "leaf.fill")
			}
		}.displayName("Ciggy Today").description("Open today's check-in.")
	}
}

struct CiggyWidgetIntentsPackage: AppIntentsPackage {
	static var includedPackages: [any AppIntentsPackage.Type] { [CiggySharedIntentsPackage.self] }
}
