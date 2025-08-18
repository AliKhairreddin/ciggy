import SwiftUI
import Charts

struct ReportsView: View {
	@EnvironmentObject private var repository: EventRepository
	@StateObject private var viewModel = ReportsViewModel()

	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					group("Last 7 Days") {
						Chart(viewModel.last7DayCounts) { item in
							BarMark(x: .value("Day", item.date, unit: .day), y: .value("Count", item.count))
						}
						.frame(height: 200)
					}
					group("Last 30 Days") {
						Chart(viewModel.last30DayCounts) { item in
							LineMark(x: .value("Day", item.date, unit: .day), y: .value("Count", item.count))
							AreaMark(x: .value("Day", item.date, unit: .day), y: .value("Count", item.count))
						}
						.frame(height: 220)
					}
					group("Heart Rate Trend (mock)") {
						Chart(viewModel.mockHeartRateTrend, id: \.0) { pair in
							LineMark(x: .value("Time", pair.0), y: .value("BPM", pair.1))
						}
						.frame(height: 220)
					}
				}
				.padding()
			}
			.navigationTitle("Reports")
		}
		.onAppear { viewModel.bind(repository: repository) }
	}

	@ViewBuilder
	private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(.headline)
			content()
		}
		.padding()
		.background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
	}
}

struct ReportsView_Previews: PreviewProvider {
	static var previews: some View {
		ReportsView()
			.environmentObject(EventRepository())
	}
}


