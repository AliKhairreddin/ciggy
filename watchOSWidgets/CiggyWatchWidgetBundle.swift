import CiggyShared
import SwiftUI
import WidgetKit

@main
struct CiggyWatchWidgetBundle: WidgetBundle {
	var body: some Widget {
		CiggyTodayWidget()
		CiggyBudgetWidget()
		CiggyElapsedWidget()
		CiggyWeekWidget()
		CiggyQuickLogWidget()
	}
}
