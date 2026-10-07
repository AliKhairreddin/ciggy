#if os(watchOS)
import Charts
import CiggyShared
import SwiftUI

struct WeeklySummaryView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@EnvironmentObject private var repository: EventRepository

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 6) {
				Text("7-day rhythm")
					.font(.system(size: 15, weight: .black, design: .rounded))
					.foregroundStyle(palette.primaryText)
				HStack(alignment: .firstTextBaseline, spacing: 4) {
					Text("\(weeklyTotal)")
						.font(.system(size: 24, weight: .black, design: .rounded))
						.foregroundStyle(palette.mint)
					Text("logged this week")
						.font(.system(size: 10))
						.foregroundStyle(palette.secondaryText)
				}

				Chart(dayCounts) { item in
					if item.count == 0 {
						PointMark(x: .value("Day", item.date, unit: .day), y: .value("Count", 0))
							.foregroundStyle(palette.secondaryText.opacity(0.45))
							.symbolSize(12)
					}
					BarMark(
						x: .value("Day", item.date, unit: .day),
						y: .value("Count", item.count)
					)
					.foregroundStyle(CiggyTheme.brandGradient)
					.cornerRadius(4)
				}
				.frame(height: 54)
				.chartYScale(domain: 0...max(1, dayCounts.map(\.count).max() ?? 0))
				.chartXAxis {
					AxisMarks(values: dayCounts.map(\.date)) { value in
						AxisValueLabel(format: .dateTime.weekday(.narrow))
							.foregroundStyle(palette.secondaryText)
					}
				}
				.chartYAxis(.hidden)

				HStack {
					Label("Avg", systemImage: "divide")
					Spacer()
					Text(String(format: "%.1f / day", Double(weeklyTotal) / 7))
				}
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(palette.secondaryText)
				.padding(8)
				.background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.padding(.horizontal, 4)
			.padding(.bottom, 8)
		}
		.containerBackground(for: .navigation) { CiggyBackdrop() }
		.toolbarForegroundStyle(palette.primaryText, for: .navigationBar)
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
