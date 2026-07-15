#if os(watchOS)
import SwiftUI
import CiggyShared

struct WatchDashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var feedbackStore: DetectionFeedbackStore
	@EnvironmentObject private var candidateStore: DetectionCandidateStore
	@EnvironmentObject private var coordinator: WatchAppCoordinator
	@StateObject private var viewModel = WatchDashboardViewModel()

	var body: some View {
		VStack(spacing: 8) {
			if viewModel.currentHeartRate > 0 {
				Text("\(Int(viewModel.currentHeartRate)) BPM")
					.font(.system(size: 22, weight: .bold))
					.accessibilityLabel("Current heart rate, \(Int(viewModel.currentHeartRate)) beats per minute")
				if viewModel.isUsingSimulatedHeartRate {
					Text("Simulated")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			} else {
				Text("Heart rate unavailable")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
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
		.sheet(isPresented: candidateIsPresented) {
			if let candidate = candidateStore.pendingCandidate {
				DetectionConfirmationView(
					candidate: candidate,
					onConfirm: {
						coordinator.confirm(
							candidate,
							repository: repository,
							feedbackStore: feedbackStore,
							candidateStore: candidateStore
						)
					},
					onDismiss: {
						coordinator.dismiss(
							candidate,
							feedbackStore: feedbackStore,
							candidateStore: candidateStore
						)
					}
				)
			}
		}
	}

	private var candidateIsPresented: Binding<Bool> {
		Binding(
			get: { candidateStore.pendingCandidate != nil },
			set: { _ in }
		)
	}
}

struct WatchDashboardView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView {
			WatchDashboardView()
				.environmentObject(EventRepository())
				.environmentObject(DetectionFeedbackStore())
				.environmentObject(DetectionCandidateStore())
				.environmentObject(WatchAppCoordinator())
		}
	}
}
#endif
