#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

struct ReportsView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@EnvironmentObject private var repository: EventRepository
	@StateObject private var viewModel = ReportsViewModel()
	@State private var range: ReportRange = .week

	private enum ReportRange: String, CaseIterable, Identifiable {
		case week = "7 days"
		case month = "30 days"
		var id: Self { self }
	}

	var body: some View {
		CiggyAdaptiveScreen {
			header
			story
			rangePicker
			activityChart
		} overview: { _ in
			header
			activityChart
		} controls: { _ in
			rangePicker
			story
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository) }
	}

	private var story: some View {
		CiggyStoryCard("Very official paperwork.", subtitle: "Your logs now have a chart department.")
	}

	private var header: some View {
		CiggyScreenHeader("The paper trail", title: "The receipts are in.", subtitle: "Cigarette counts. With charts, naturally.")
	}

	private var rangePicker: some View {
		Picker("Report range", selection: $range) {
			ForEach(ReportRange.allCases) { option in
				Text(option.rawValue).tag(option)
			}
		}
		.pickerStyle(.segmented)
		.accessibilityIdentifier("report-range-picker")
	}

	private var activityChart: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				HStack(alignment: .firstTextBaseline) {
					VStack(alignment: .leading, spacing: 2) {
						Text(range == .week ? "Daily counts" : "30-day counts")
							.font(.headline)
							.foregroundStyle(palette.primaryText)
					}
					Spacer()
					Text("\(visibleCounts.reduce(0) { $0 + $1.count }) total")
						.font(.caption.weight(.bold))
						.foregroundStyle(palette.mint)
				}

				if visibleCounts.allSatisfy({ $0.count == 0 }) {
					Label("No logs in this range. No receipts to print.", systemImage: "pencil.and.scribble")
						.font(.caption).foregroundStyle(palette.secondaryText)
				}

				Chart(visibleCounts) { item in
					if range == .week {
						BarMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(CiggyTheme.emberGradient)
						.cornerRadius(6)
					} else {
						AreaMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(
							LinearGradient(
								colors: [palette.mint.opacity(0.42), palette.mint.opacity(0.02)],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						LineMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(palette.mint)
						.lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
					}
				}
				.frame(height: 240)
				.chartXAxis {
					AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 6)) { _ in
						AxisValueLabel(format: .dateTime.day().month(.abbreviated))
							.foregroundStyle(palette.secondaryText)
					}
				}
				.chartYScale(domain: 0...max(1, (visibleCounts.map(\.count).max() ?? 0)))
				.chartYAxis {
					AxisMarks(position: .leading) { _ in
						AxisGridLine().foregroundStyle(palette.border)
						AxisValueLabel().foregroundStyle(palette.secondaryText)
					}
				}
			}
		}
	}

	private var visibleCounts: [DayCount] {
		range == .week ? viewModel.last7DayCounts : viewModel.last30DayCounts
	}
}

struct ReportsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			ReportsView().environmentObject(EventRepository())
		}
	}
}
#endif
