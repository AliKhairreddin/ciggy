#if os(watchOS)
import SwiftUI
import CiggyShared

struct LogSmokeView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var notes: String = ""

	var body: some View {
		Form {
			Section(header: Text("Confirm")) {
				Text("Log a smoking event?")
			}
			Section(header: Text("Notes (optional)")) {
				TextField("Add a note", text: $notes)
			}
			Section {
				Button("Save") { save() }
				Button("Cancel") { dismiss() }.tint(.red)
			}
		}
		.navigationTitle("Log Smoke")
	}

	private func save() {
		let currentHeartRate = HealthKitManager.shared.currentHeartRate
		let event = SmokingEvent(
			timestamp: Date(),
			source: .manual,
			heartRate: currentHeartRate > 0 ? currentHeartRate : nil,
			notes: notes.isEmpty ? nil : notes
		)
		repository.addEvent(event)
		ConnectivityManager.shared.send(event: event)
		dismiss()
	}
}

struct LogSmokeView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView { LogSmokeView().environmentObject(EventRepository()) }
	}
}
#endif
