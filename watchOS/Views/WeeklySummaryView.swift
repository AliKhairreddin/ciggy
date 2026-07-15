#if os(watchOS)
import Charts
import CiggyShared
import SwiftUI

struct WeeklySummaryView: View {
	@EnvironmentObject private var repository: EventRepository

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 10) {
					Text("7-day rhythm")
						.font(.system(size: 19, weight: .black, design: .rounded))
						.foregroundStyle(.white)
					HStack(alignment: .firstTextBaseline, spacing: 4) {
						Text("\(weeklyTotal)")
							.font(.system(size: 32, weight: .black, design: .rounded))
							.foregroundStyle(CiggyTheme.mint)
						Text("logged this week")
							.font(.system(size: 10))
							.foregroundStyle(CiggyTheme.secondaryText)
					}

					Chart(dayCounts) { item in
						BarMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(CiggyTheme.brandGradient)
						.cornerRadius(4)
					}
					.frame(height: 100)
					.chartXAxis(.hidden)
					.chartYAxis(.hidden)

					HStack {
						Label("Avg", systemImage: "divide")
						Spacer()
						Text(String(format: "%.1f / day", Double(weeklyTotal) / 7))
					}
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(CiggyTheme.secondaryText)
					.padding(10)
					.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
				.padding(.horizontal, 4)
			}
		}
		.navigationTitle("Weekly")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var dayCounts: [DayCount] {
		ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
	}

	private var weeklyTotal: Int {
		dayCounts.reduce(0) { $0 + $1.count }
	}
}

struct WeeklySummaryView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			WeeklySummaryView().environmentObject(EventRepository())
		}
	}
}
#endif
