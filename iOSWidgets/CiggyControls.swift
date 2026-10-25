import AppIntents
import CiggyShared
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct CiggyLogControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyLogControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .log)) {
				Label { Text("Log a Cigarette") } icon: { CiggyIcon.log.image }
			}
		}.displayName("Log a Cigarette").description("Open the logging form. Save the cigarette in Ciggy.")
	}
}

@available(iOS 18.0, *)
struct CiggyReportsControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyReportsControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .reports)) {
				Label { Text("Reports") } icon: { CiggyIcon.reports.image }
			}
		}.displayName("Ciggy Reports").description("Open your trends and reports.")
	}
}

@available(iOS 18.0, *)
struct CiggyTodayControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "CiggyTodayControl") {
			ControlWidgetButton(action: OpenCiggyScreenIntent(target: .today)) {
				Label { Text("Cigarettes Today") } icon: { CiggyIcon.cigarette.image }
			}
		}.displayName("Cigarettes Today").description("Open today's recorded cigarette count in Ciggy.")
	}
}
