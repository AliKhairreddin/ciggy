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
			heartRateCard
			evidenceNote
		} overview: { _ in
			header
			activityChart
		} controls: { _ in
			rangePicker
			story
			heartRateCard
			evidenceNote
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository) }
	}

	private var story: some View {
		CiggyStoryCard("Connect the little dots.", subtitle: "Your habits have a rhythm. Let’s find it.")
	}

	private var header: some View {
		CiggyScreenHeader("The bigger picture", title: "You've got a rhythm.", subtitle: "A little curiosity goes a long way.")
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
						Text(range == .week ? "Daily activity" : "Monthly trend")
							.font(.headline)
							.foregroundStyle(palette.primaryText)
						Text("Manual and automatic logs")
							.font(.caption)
							.foregroundStyle(palette.secondaryText)
					}
					Spacer()
					Text("\(visibleCounts.reduce(0) { $0 + $1.count }) total")
						.font(.caption.weight(.bold))
						.foregroundStyle(palette.mint)
				}

				if visibleCounts.allSatisfy({ $0.count == 0 }) {
					Label("A blank page for now. Your logs will fill it in.", systemImage: "pencil.and.scribble")
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

	private var heartRateCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Image(systemName: "heart.fill")
						.foregroundStyle(CiggyTheme.ember)
					Text("Heart-rate context")
						.font(.headline)
						.foregroundStyle(palette.primaryText)
					Spacer()
					Text("Optional")
						.font(.caption2.weight(.bold))
						.foregroundStyle(CiggyTheme.ember)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(CiggyTheme.ember.opacity(0.12), in: Capsule())
				}

				if viewModel.heartRateTrend.isEmpty {
					HStack(spacing: 12) {
						Image(systemName: "waveform.path.ecg")
							.font(.title2)
							.foregroundStyle(palette.secondaryText)
						Text("No heart-rate samples are attached to logged events yet.")
							.font(.subheadline)
							.foregroundStyle(palette.secondaryText)
					}
					.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
				} else {
					Chart(viewModel.heartRateTrend, id: \.0) { pair in
						LineMark(x: .value("Time", pair.0), y: .value("BPM", pair.1))
							.foregroundStyle(CiggyTheme.ember)
						PointMark(x: .value("Time", pair.0), y: .value("BPM", pair.1))
							.foregroundStyle(CiggyTheme.sunlight)
					}
					.frame(height: 190)
				}
			}
		}
	}

	private var evidenceNote: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "hand.raised.fingers.spread")
				.foregroundStyle(palette.mint)
			Text("Automatic events begin with repeated wrist motion. Heart rate can add context, but it never decides whether you smoked.")
				.font(.caption)
				.foregroundStyle(palette.secondaryText)
		}
		.padding(.horizontal, 4)
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
