#if os(iOS)
import CiggyShared
import SwiftUI

struct LiveActivityCard: View {
	@EnvironmentObject private var liveActivity: LiveActivityManager
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }

	var body: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				Label("The lock-screen edition", systemImage: "capsule")
					.font(.headline).foregroundStyle(palette.primaryText)
				Text("Your tally. On the Lock Screen.")
					.font(.caption).foregroundStyle(palette.secondaryText)
				Button {
					Task {
						if liveActivity.isActive { await liveActivity.stop() }
						else { await liveActivity.start() }
					}
				} label: {
					Label(liveActivity.isActive ? "Stop Live Activity" : "Start Live Activity",
					      systemImage: liveActivity.isActive ? "stop.circle" : "play.circle")
						.font(.subheadline.weight(.bold))
						.frame(maxWidth: .infinity).padding(.vertical, 12)
						.ciggyGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
				}
				.buttonStyle(.plain).foregroundStyle(palette.primaryText)
				.disabled(liveActivity.isBusy || (!liveActivity.activitiesEnabled && !liveActivity.isActive))
				.accessibilityIdentifier("live-activity-button")
				if !liveActivity.activitiesEnabled {
					Text("Live Activities are disabled. Enable them in iPhone Settings → Ciggy.")
						.font(.caption).foregroundStyle(palette.secondaryText)
				}
				if let message = liveActivity.errorMessage {
					Text(message).font(.caption).foregroundStyle(palette.secondaryText)
						.accessibilityIdentifier("live-activity-error")
				}
			}
		}
	}
}
#endif
