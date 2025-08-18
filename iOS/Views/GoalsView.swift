import SwiftUI

struct GoalsView: View {
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = GoalsViewModel()

	var body: some View {
		Form {
			Section(header: Text("Quit Plan")) {
				DatePicker("Quit Date", selection: Binding(
					get: { viewModel.quitDate ?? Date() },
					set: { viewModel.quitDate = $0 }
				), displayedComponents: .date)
			}
			Section(header: Text("Daily Limit")) {
				Stepper(value: $viewModel.dailyLimit, in: 1...100) {
					Text("Daily limit: \(viewModel.dailyLimit)")
				}
			}
			Section(footer: Text("Set realistic reduction goals to build momentum.")) {
				Stepper(value: $viewModel.reductionGoal, in: 0...max(0, viewModel.dailyLimit-1)) {
					Text("Reduce by: \(viewModel.reductionGoal) / day")
				}
			}
			Section {
				Button("Save Goals") { viewModel.save(settings: settings) }
			}
		}
		.navigationTitle("Goals")
		.onAppear { viewModel.bind(settings: settings) }
	}
}

struct GoalsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView { GoalsView().environmentObject(UserSettingsStore()) }
	}
}


