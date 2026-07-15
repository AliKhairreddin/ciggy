#if os(iOS)
import SwiftUI
import CiggyShared

struct SettingsView: View {
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = SettingsViewModel()

	var body: some View {
		Form {
			Section(header: Text("Notifications")) {
				Toggle("Enable notifications", isOn: $viewModel.notificationsEnabled)
			}
			Section(header: Text("Detection Sensitivity"), footer: Text("Higher sensitivity may increase false positives.")) {
				Slider(value: $viewModel.sensitivity, in: 0...1) {
					Text("Sensitivity")
				}
			}
			Section(header: Text("Privacy")) {
				NavigationLink(destination: PrivacyInfoView()) {
					Text("How Ciggy Uses Data")
				}
			}
			Section {
				Button("Save Settings") {
					Task { await viewModel.save(settings: settings) }
				}
			}
		}
		.navigationTitle("Settings")
		.onAppear { viewModel.bind(settings: settings) }
	}
}

private struct PrivacyInfoView: View {
	var body: some View {
		List {
			Section("Stored on this device") {
				Text("Ciggy stores smoking events, optional notes, settings, and detection feedback locally on your devices.")
			}
			Section("Apple Watch sync") {
				Text("Confirmed events and settings move between your paired iPhone and Apple Watch using WatchConnectivity.")
			}
			Section("Health data") {
				Text("If you grant access, Ciggy reads heart-rate samples from HealthKit to support possible-event detection. It does not write HealthKit data.")
			}
			Section("Cloud services") {
				Text("This prototype does not upload your events, notes, settings, or detection feedback to a cloud service.")
			}
		}
		.navigationTitle("Your Data")
		.navigationBarTitleDisplayMode(.inline)
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView { SettingsView().environmentObject(UserSettingsStore()) }
	}
}
#endif
