#if os(watchOS)
import CiggyShared
import SwiftUI

struct DetectionConfirmationView: View {
	let candidate: DetectionCandidate
	let onConfirm: () -> Void
	let onDismiss: () -> Void

	var body: some View {
		ScrollView {
			VStack(spacing: 10) {
				Image(systemName: "questionmark.circle.fill")
					.font(.title2)
					.foregroundStyle(.orange)
				Text("Possible smoking event?")
					.font(.headline)
					.multilineTextAlignment(.center)
				Text("Your motion and heart rate matched a possible event. You decide whether it counts.")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)

				Button("Yes, log it", action: onConfirm)
					.buttonStyle(.borderedProminent)
				Button("No, dismiss", role: .cancel, action: onDismiss)
					.buttonStyle(.bordered)
			}
			.padding()
		}
		.interactiveDismissDisabled()
	}
}
#endif
