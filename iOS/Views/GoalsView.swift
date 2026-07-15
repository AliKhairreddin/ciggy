#if os(iOS)
import SwiftUI
import CiggyShared

struct GoalsView: View {
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = GoalsViewModel()

	var body: some View {
		Form {
			Section(header: Text("Quit Plan")) {
				Toggle("Set a quit date", isOn: $viewModel.hasQuitDate)
				if viewModel.hasQuitDate {
					DatePicker("Quit Date", selection: Binding(
						get: { viewModel.quitDate ?? Date() },
						set: { viewModel.quitDate = $0 }
					), displayedComponents: .date)
				}
			}
			Section(
				header: Text("Daily Limit"),
				footer: Text("Set a realistic limit you can reduce over time.")
			) {
				Stepper(value: $viewModel.dailyLimit, in: 1...100) {
					Text("Daily limit: \(viewModel.dailyLimit)")
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
#endif
