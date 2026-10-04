import CiggyShared
import SwiftUI
import WidgetKit

@main
struct CiggyWidgetBundle: WidgetBundle {
	var body: some Widget {
		CiggyTodayWidget()
		CiggyBudgetWidget()
		CiggyElapsedWidget()
		CiggyWeekWidget()
		CiggyQuickLogWidget()
		CiggyLiveActivity()
		if #available(iOS 18.0, *) {
			CiggyLogControl()
			CiggyReportsControl()
			CiggyTodayControl()
		}
	}
}
