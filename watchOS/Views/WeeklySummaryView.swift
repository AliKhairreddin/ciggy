import SwiftUI
import Charts

struct WeeklySummaryView: View {
	@EnvironmentObject private var repository: EventRepository

	var body: some View {
		VStack(alignment: .leading) {
			Text("Weekly Summary").font(.headline)
			Chart(ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)) { item in
				BarMark(x: .value("Day", item.date, unit: .day), y: .value("Count", item.count))
			}
			.frame(height: 120)
		}
		.padding()
		.navigationTitle("Weekly")
	}
}

struct WeeklySummaryView_Previews: PreviewProvider {
	static var previews: some View {
		WeeklySummaryView().environmentObject(EventRepository())
	}
}


