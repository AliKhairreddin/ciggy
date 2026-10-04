#if os(iOS)
import CiggyShared
import SwiftUI

struct PhoneLogSmokeView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var repository: EventRepository
	@State private var localNotes = ""
	var notes: Binding<String>? = nil
	@State private var didSave = false
	let onSave: (SmokingEvent) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					PhoneLogSmokeForm(notes: notes ?? $localNotes, didSave: didSave, onSave: save)
				}.padding(24)
			}
			.foregroundStyle(palette.primaryText)
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
		let event = PhoneSmokingLog.save(notes: notes?.wrappedValue ?? localNotes, repository: repository)
		notes?.wrappedValue = ""
		localNotes = ""
		onSave(event)
		dismiss()
	}
}
/// Shared by the sheet and the lower half of the foldable display.
struct PhoneLogSmokeForm: View {
	@Environment(\.colorScheme) private var colorScheme
	@FocusState private var isEditingNotes: Bool
	@Binding var notes: String
	let didSave: Bool
	let onSave: () -> Void
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			HStack(spacing: 20) {
				VStack(alignment: .leading, spacing: 6) {
					Text("Just a check-in.").font(.system(.title, design: .rounded, weight: .black)).tracking(-1)
					Text("One cigarette. Zero judgment.").font(.subheadline).foregroundStyle(palette.secondaryText)
				}
				Spacer(minLength: 0)
				CiggyBrandMark(size: 48)
			}
			TextField("Add a note (optional)", text: $notes, axis: .vertical)
				.lineLimit(2...4).padding(18)
				.background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
				.accessibilityIdentifier("phone-log-note")
				.disabled(didSave)
				.focused($isEditingNotes)
			Button(action: onSave) {
				Label(didSave ? "Cigarette logged" : "Save 1 cigarette", systemImage: "checkmark")
					.font(.headline).frame(maxWidth: .infinity).padding(18)
					.ciggyGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
			}.buttonStyle(.plain).disabled(didSave).accessibilityIdentifier("save-phone-log")
			Text("Added to today and sent to your paired Watch.").font(.caption).foregroundStyle(palette.secondaryText)
		}.foregroundStyle(palette.primaryText)
		.toolbar {
			ToolbarItemGroup(placement: .keyboard) {
				Spacer()
				Button("Done") { isEditingNotes = false }
			}
		}
	}
}

@MainActor
enum PhoneSmokingLog {
	static func save(notes: String, repository: EventRepository) -> SmokingEvent {
		let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
		let event = SmokingEvent(source: .manual, notes: note.isEmpty ? nil : note)
		repository.addEvent(event)
		ConnectivityManager.shared.send(event: event)
		return event
	}
}
#endif
