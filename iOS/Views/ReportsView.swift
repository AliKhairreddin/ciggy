#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

struct ReportsView: View {
	@EnvironmentObject private var repository: EventRepository
	@StateObject private var viewModel = ReportsViewModel()
	@State private var range: ReportRange = .week

	private enum ReportRange: String, CaseIterable, Identifiable {
		case week = "7 days"
		case month = "30 days"
		var id: Self { self }
	}

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					header
					rangePicker
					activityChart
					heartRateCard
					evidenceNote
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				.padding(.bottom, 28)
			}
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository) }
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text("Your rhythm")
				.font(.system(size: 34, weight: .black, design: .rounded))
				.foregroundStyle(.white)
			Text("Patterns become easier to change once you can see them.")
				.font(.subheadline)
				.foregroundStyle(CiggyTheme.secondaryText)
		}
	}

	private var rangePicker: some View {
		Picker("Report range", selection: $range) {
			ForEach(ReportRange.allCases) { option in
				Text(option.rawValue).tag(option)
			}
		}
		.pickerStyle(.segmented)
		.colorScheme(.dark)
	}

	private var activityChart: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				HStack(alignment: .firstTextBaseline) {
					VStack(alignment: .leading, spacing: 2) {
						Text(range == .week ? "Daily activity" : "Monthly trend")
							.font(.headline)
							.foregroundStyle(.white)
						Text("Confirmed and manual logs")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer()
					Text("\(visibleCounts.reduce(0) { $0 + $1.count }) total")
						.font(.caption.weight(.bold))
						.foregroundStyle(CiggyTheme.mint)
				}

				Chart(visibleCounts) { item in
					if range == .week {
						BarMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(CiggyTheme.brandGradient)
						.cornerRadius(6)
					} else {
						AreaMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(
							LinearGradient(
								colors: [CiggyTheme.mint.opacity(0.42), CiggyTheme.mint.opacity(0.02)],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						LineMark(
							x: .value("Day", item.date, unit: .day),
							y: .value("Count", item.count)
						)
						.foregroundStyle(CiggyTheme.mint)
						.lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
					}
				}
				.frame(height: 240)
				.chartXAxis {
					AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 6)) { _ in
						AxisValueLabel(format: .dateTime.day().month(.abbreviated))
							.foregroundStyle(CiggyTheme.secondaryText)
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading) { _ in
						AxisGridLine().foregroundStyle(CiggyTheme.border)
						AxisValueLabel().foregroundStyle(CiggyTheme.secondaryText)
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
						.foregroundStyle(.white)
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
							.foregroundStyle(CiggyTheme.secondaryText)
						Text("No heart-rate samples are attached to logged events yet.")
							.font(.subheadline)
							.foregroundStyle(CiggyTheme.secondaryText)
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
				.foregroundStyle(CiggyTheme.mint)
			Text("Automatic events begin with repeated wrist motion. Heart rate can add context, but it never decides whether you smoked.")
				.font(.caption)
				.foregroundStyle(CiggyTheme.secondaryText)
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
