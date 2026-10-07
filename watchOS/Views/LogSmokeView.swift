#if os(watchOS)
import CiggyShared
import SwiftUI

struct LogSmokeView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var notes = ""

	var body: some View {
		ScrollView {
			VStack(spacing: 6) {
				HStack(spacing: 6) {
					VStack(alignment: .leading, spacing: 2) {
						Text("Just a check-in.")
							.font(.system(size: 14, weight: .black, design: .rounded))
							.foregroundStyle(palette.primaryText)
						Text("Zero judgment.")
							.font(.system(size: 9))
							.foregroundStyle(palette.secondaryText)
					}
					Spacer(minLength: 0)
					CiggyMascot(animated: false).frame(width: 32, height: 32)
				}

				TextField("Optional note", text: $notes)
					.textFieldStyle(.plain)
					.font(.system(size: 12))
					.foregroundStyle(palette.primaryText)
					.padding(6)
					.background(palette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

				Button(action: save) {
					Label("Save 1", systemImage: "checkmark")
						.font(.system(size: 14, weight: .bold))
						.foregroundStyle(CiggyTheme.deepInk)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 9)
						.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, 4)
			.padding(.bottom, 8)
		}
		.containerBackground(for: .navigation) { CiggyBackdrop() }
		.toolbarForegroundStyle(palette.primaryText, for: .navigationBar)
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
