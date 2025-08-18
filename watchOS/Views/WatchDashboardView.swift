import SwiftUI

struct WatchDashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@StateObject private var viewModel = WatchDashboardViewModel()

	var body: some View {
		VStack(spacing: 8) {
			Text("\(Int(viewModel.currentHeartRate)) BPM")
				.font(.system(size: 22, weight: .bold))
			Text("Today: \(viewModel.todayCount)")
			Text("Last: \(viewModel.timeSinceLast)")
			NavigationLink(destination: LogSmokeView()) {
				Text("Log Smoke")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding(8)
					.background(Color.accentColor)
					.cornerRadius(8)
			}
			NavigationLink(destination: WeeklySummaryView()) { Text("Weekly Summary") }
		}
		.padding()
		.onAppear { viewModel.bind(repository: repository) }
	}
}

struct WatchDashboardView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView { WatchDashboardView().environmentObject(EventRepository()) }
	}
}


