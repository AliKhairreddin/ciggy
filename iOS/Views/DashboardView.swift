#if os(iOS)
import SwiftUI
import Charts
import CiggyShared

struct DashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = DashboardViewModel()

	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					metrics
					progress
					chart
				}
				.padding()
			}
			.navigationTitle("Dashboard")
		}
		.onAppear { viewModel.bind(repository: repository, settings: settings) }
	}

	private var metrics: some View {
		HStack(spacing: 12) {
			metricCard(title: "Today", value: "\(viewModel.dailyCount)")
			metricCard(title: "Week", value: "\(viewModel.weeklyCount)")
			metricCard(title: "Month", value: "\(viewModel.monthlyCount)")
		}
	}

	private var progress: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Daily Limit: \(settings.settings.dailyLimit)")
				.font(.subheadline)
			ProgressView(value: viewModel.todayProgress)
				.progressViewStyle(.linear)
			Text("Last event: \(viewModel.lastEventDescription)")
				.font(.footnote)
			Text("Streak: \(viewModel.streakDays) days smoke-free")
				.font(.footnote)
			Text(String(format: "Money saved: $%.2f", viewModel.moneySaved))
				.font(.footnote)
		}
		.padding()
		.background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
	}

	private var chart: some View {
		VStack(alignment: .leading) {
			Text("Last 7 days")
				.font(.headline)
			Chart(ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)) { item in
				BarMark(
					x: .value("Day", item.date, unit: .day),
					y: .value("Count", item.count)
				)
			}
			.frame(height: 180)
		}
		.padding()
		.background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
	}

	private func metricCard(title: String, value: String) -> some View {
		VStack {
			Text(value)
				.font(.title)
				.bold()
			Text(title)
				.font(.caption)
		}
		.frame(maxWidth: .infinity)
		.padding()
		.background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
	}
}

struct DashboardView_Previews: PreviewProvider {
	static var previews: some View {
		DashboardView()
			.environmentObject(EventRepository())
			.environmentObject(UserSettingsStore())
	}
}
#endif
