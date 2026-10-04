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
				Label("Live Activity", systemImage: "capsule")
					.font(.headline).foregroundStyle(palette.primaryText)
				Text("Keep today's count, your limit, and time since your last log on the Lock Screen and Dynamic Island on supported iPhones.")
					.font(.caption).foregroundStyle(palette.secondaryText)
				Text("Visible outside Ciggy. Sessions last up to 8 hours, ending by midnight.")
					.font(.caption2).foregroundStyle(palette.secondaryText)
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
