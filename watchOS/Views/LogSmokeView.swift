#if os(watchOS)
import CiggyShared
import SwiftUI

struct LogSmokeView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var notes = ""
	@State private var didSave = false
	@State private var saveError: String?

	var body: some View {
		ScrollView {
			VStack(spacing: 6) {
				HStack(spacing: 6) {
					VStack(alignment: .leading, spacing: 2) {
						Text("For the record.")
							.font(.system(size: 14, weight: .black, design: .rounded))
							.foregroundStyle(palette.primaryText)
						Text("One cigarette. On file.")
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

				if let saveError {
					Text(saveError).font(.caption2).foregroundStyle(palette.secondaryText)
						.accessibilityIdentifier("watch-log-save-error")
				}
				Button(action: save) {
					Label(saveError == nil ? "Save 1" : "Retry save", systemImage: "checkmark")
						.font(.system(size: 14, weight: .bold))
						.foregroundStyle(CiggyTheme.deepInk)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 9)
						.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
				}
				.buttonStyle(.plain)
				.disabled(didSave)
				.accessibilityIdentifier("save-watch-log")
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
		guard !didSave else { return }
		let now = Date()
		let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
		let event = SmokingEvent(
			timestamp: now,
			source: .manual,
			heartRate: HealthKitManager.shared.freshHeartRate(at: now),
			notes: trimmedNotes.isEmpty ? nil : trimmedNotes
		)
		guard repository.addEvent(event) else {
			saveError = repository.lastPersistenceError ?? "Couldn't save your cigarette. Your note is still here; try again."
			return
		}
		didSave = true
		saveError = nil
		dismiss()
	}
}

struct LogSmokeView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack { LogSmokeView().environmentObject(EventRepository()) }
	}
}
#endif
