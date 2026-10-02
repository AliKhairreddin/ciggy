#if os(iOS)
import CiggyShared
import SwiftUI

struct PhoneLogSmokeView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var notes = ""
	@State private var didSave = false
	let onSave: (SmokingEvent) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					HStack(spacing: 20) {
						VStack(alignment: .leading, spacing: 6) {
							Text("Just a check-in.").font(.system(.title, design: .rounded, weight: .black)).tracking(-1)
							Text("One cigarette. Zero judgment.").font(.subheadline).foregroundStyle(CiggyTheme.secondaryText)
						}
						Spacer(minLength: 0)
						CiggyBrandMark(size: 64)
					}
					TextField("Add a note (optional)", text: $notes, axis: .vertical)
						.lineLimit(2...4).padding(18)
						.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
						.accessibilityIdentifier("phone-log-note")
					Button(action: save) {
						Label("Save 1 cigarette", systemImage: "checkmark")
							.font(.headline).frame(maxWidth: .infinity).padding(18)
							.ciggyGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
					}.buttonStyle(.plain).disabled(didSave).accessibilityIdentifier("save-phone-log")
					Text("Added to today and sent to your paired Watch.").font(.caption).foregroundStyle(CiggyTheme.secondaryText)
				}.padding(24)
			}
			.foregroundStyle(CiggyTheme.ink)
			.scrollDismissesKeyboard(.interactively)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
			}
		}
		.tint(CiggyTheme.ember)
	}

	private func save() {
		guard !didSave else { return }
		didSave = true
		let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
		let event = SmokingEvent(source: .manual, notes: note.isEmpty ? nil : note)
		repository.addEvent(event)
		ConnectivityManager.shared.send(event: event)
		onSave(event)
		dismiss()
	}
}
#endif
