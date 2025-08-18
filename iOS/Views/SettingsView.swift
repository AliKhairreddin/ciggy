import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = SettingsViewModel()

	var body: some View {
		Form {
			Section(header: Text("Notifications")) {
				Toggle("Enable notifications", isOn: $viewModel.notificationsEnabled)
				Button("Request Permission") {
					Task { _ = await NotificationManager.requestAuthorization() }
				}
			}
			Section(header: Text("Detection Sensitivity"), footer: Text("Higher sensitivity may increase false positives.")) {
				Slider(value: $viewModel.sensitivity, in: 0...1) {
					Text("Sensitivity")
				}
			}
			Section(header: Text("Privacy")) {
				NavigationLink(destination: Text("Privacy policy placeholder")) {
					Text("Privacy Policy")
				}
			}
			Section {
				Button("Save Settings") { viewModel.save(settings: settings) }
			}
		}
		.navigationTitle("Settings")
		.onAppear { viewModel.bind(settings: settings) }
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView { SettingsView().environmentObject(UserSettingsStore()) }
	}
}


