import ActivityKit
import CiggyShared
import SwiftUI
import WidgetKit

struct CiggyLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: CiggyActivityAttributes.self) { context in
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label("ciggy", systemImage: "leaf.fill").font(.headline)
					Spacer()
					Text(context.isStale ? "Session ended" : "Today's check-in").font(.caption)
				}
				if context.isStale {
					Text("Open Ciggy to start another session.").font(.subheadline)
				} else {
					HStack(alignment: .top) {
						count(context)
						Spacer()
						elapsed(context)
					}
					ProgressView(value: context.state.progress).tint(CiggyTheme.ember).privacySensitive()
					HStack {
						Text("\(context.state.remaining) remaining within your limit").font(.caption).privacySensitive()
						Spacer()
						Link(destination: URL(string: "ciggy://log")!) {
							Label("Log", systemImage: "plus.circle.fill").font(.subheadline.weight(.bold))
						}
					}
				}
			}.padding(16)
				.activityBackgroundTint(CiggyTheme.paper)
				.activitySystemActionForegroundColor(CiggyTheme.ink)
				.foregroundStyle(CiggyTheme.ink)
				.widgetURL(URL(string: "ciggy://today"))
		} dynamicIsland: { context in
			DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					Label("ciggy", systemImage: "leaf.fill").font(.headline).foregroundStyle(CiggyTheme.peach)
				}
				DynamicIslandExpandedRegion(.trailing) {
					if !context.isStale {
						Text("\(context.state.dailyCount)/\(context.state.dailyLimit)")
							.font(.headline).monospacedDigit().privacySensitive()
					}
				}
				DynamicIslandExpandedRegion(.bottom) {
					if context.isStale {
						Text("Session ended · Open Ciggy").font(.caption)
					} else {
						VStack(spacing: 10) {
							ProgressView(value: context.state.progress).tint(CiggyTheme.peach).privacySensitive()
							HStack {
								elapsed(context)
								Spacer()
								Link(destination: URL(string: "ciggy://log")!) { Label("Log", systemImage: "plus.circle.fill") }
									.font(.subheadline.weight(.bold)).foregroundStyle(CiggyTheme.peach)
							}
						}
					}
				}
			} compactLeading: {
				Image(systemName: "leaf.fill").foregroundStyle(CiggyTheme.peach)
			} compactTrailing: {
				if context.isStale { Image(systemName: "checkmark") }
				else { Text("\(context.state.dailyCount)").monospacedDigit().privacySensitive() }
			} minimal: {
				Image(systemName: "leaf.fill").foregroundStyle(CiggyTheme.peach)
			}
			.widgetURL(URL(string: "ciggy://today"))
			.keylineTint(CiggyTheme.peach)
		}
	}

	private func count(_ context: ActivityViewContext<CiggyActivityAttributes>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text("\(context.state.dailyCount) / \(context.state.dailyLimit)").font(.title2.weight(.black)).monospacedDigit()
			Text("cigarettes today").font(.caption)
		}.privacySensitive()
	}

	private func elapsed(_ context: ActivityViewContext<CiggyActivityAttributes>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			if let last = context.state.lastLoggedAt {
				Text(timerInterval: last...context.attributes.expiresAt, countsDown: false)
					.font(.headline).monospacedDigit().privacySensitive()
				Text("since last log").font(.caption2)
			} else { Text("No logs yet").font(.caption) }
		}
	}
}
