#if os(watchOS)
import CiggyShared
import SwiftUI

struct LogSmokeView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var notes = ""

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(spacing: 12) {
					CiggyBrandMark(size: 42)
					Text("Log 1 cigarette")
						.font(.system(size: 19, weight: .black, design: .rounded))
						.foregroundStyle(.white)
					Text("Add it now, without judgment.")
						.font(.system(size: 10))
						.foregroundStyle(CiggyTheme.secondaryText)

					TextField("Optional note", text: $notes)
						.textFieldStyle(.plain)
						.padding(10)
						.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

					Button(action: save) {
						Label("Save 1", systemImage: "checkmark")
							.font(.headline)
							.foregroundStyle(CiggyTheme.deepInk)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 11)
							.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
					}
					.buttonStyle(.plain)

					Button("Cancel") { dismiss() }
						.buttonStyle(.plain)
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(CiggyTheme.secondaryText)
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 8)
			}
		}
		.navigationTitle("Log")
		.navigationBarTitleDisplayMode(.inline)
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
		NavigationStack { LogSmokeView().environmentObject(EventRepository()) }
	}
}
#endif
