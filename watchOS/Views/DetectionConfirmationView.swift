#if os(watchOS)
import CiggyShared
import SwiftUI

struct DetectionConfirmationView: View {
	let candidate: DetectionCandidate
	let pendingCount: Int
	let onConfirm: () -> Void
	let onDismiss: () -> Void

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(spacing: 10) {
					ZStack {
						Circle()
							.fill(CiggyTheme.ember.opacity(0.14))
						Image(systemName: "hand.raised.fingers.spread.fill")
							.font(.title2)
							.foregroundStyle(CiggyTheme.ember)
					}
					.frame(width: 50, height: 50)

					Text("Smoked 1?")
						.font(.system(size: 23, weight: .black, design: .rounded))
						.foregroundStyle(.white)

					Text(evidenceText)
						.font(.system(size: 11))
						.foregroundStyle(CiggyTheme.secondaryText)
						.multilineTextAlignment(.center)

					if pendingCount > 1 {
						Text("1 of \(pendingCount) possible events")
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(CiggyTheme.sunlight)
					}

					Button(action: onConfirm) {
						Label("Yes, log 1", systemImage: "checkmark")
							.font(.headline)
							.foregroundStyle(CiggyTheme.deepInk)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 10)
							.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
					}
					.buttonStyle(.plain)

					Button(action: onDismiss) {
						Text("No, not this time")
							.font(.system(size: 13, weight: .semibold))
							.foregroundStyle(.white)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 9)
							.background(CiggyTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
					}
					.buttonStyle(.plain)
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 6)
			}
		}
		.interactiveDismissDisabled()
	}

	private var evidenceText: String {
		let count = candidate.motionGestureCount ?? 0
		let dateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(candidate.gestureAt)
			? .omitted
			: .abbreviated
		let time = candidate.gestureAt.formatted(date: dateStyle, time: .shortened)
		if count > 0 {
			return "Around \(time), Ciggy noticed \(count) repeated hand-to-mouth movements. You make the call."
		}
		return "Around \(time), Ciggy noticed a repeated hand-to-mouth pattern. You make the call."
	}
}
#endif
