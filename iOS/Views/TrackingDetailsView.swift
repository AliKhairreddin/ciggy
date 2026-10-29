#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

/// Technical explanations live here, away from the daily count.
struct TrackingDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var repository: EventRepository
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @ObservedObject private var tracking = TrackingStatusStore.shared
    @StateObject private var viewModel = ReportsViewModel()
    private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    trackingStatusCard(at: context.date)
                }
                CiggyPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How counting works").font(.headline)
                        Text("Wear your Watch on the hand you smoke with. Ciggy looks for repeated gestures; detection can miss cigarettes or mistake other movements. Review and adjust your total when needed.")
                        Text("Counts are estimates from recorded wrist motion. Heart rate can add context, but it never decides whether you smoked.")
                        Text("Ciggy requests background checks about every 15 minutes. watchOS chooses when to run them, so this is not a guaranteed schedule. A Ciggy complication on your active Watch face gives the app more background opportunities.")
                        Text("Watch logs and corrections sync with your paired iPhone. The time beside a log is the cigarette's timestamp, not the time it arrived on this device.")
                        Text("A review appears after an automatic estimate is saved. New estimates join the pending review for that day; a check with no new detections does not create a zero-count review. Estimated log times are not proof that every moment between them was checked, or that no cigarettes were missed.")
                        Text("Sitting and standing can both produce matching gestures. Ciggy compares wrist orientation across all three motion axes with your resting pose; it does not measure hand height. Small movements or a different return pose can be missed. Normal sensitivity needs five completed gestures over at least five minutes; shorter activity can be missed too.")
                        Text(connectivity.isLiveSyncAvailable ? "Watch connection: live" : "Watch connection: waiting for background delivery")
                    }
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                }
                heartRateCard
                CiggyPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Live Activity").font(.headline)
                        Text("The Today screen can start a Live Activity showing your count, daily limit and time since your last log on the Lock Screen and Dynamic Island on supported iPhones. It is visible outside Ciggy. Sessions last up to eight hours and end by midnight.")
                    }.font(.subheadline).foregroundStyle(palette.primaryText)
                }
            }.padding(20)
        }
        .background { CiggyBackdrop() }
        .navigationTitle("Tracking details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { viewModel.bind(repository: repository) }
    }

	private func trackingStatusCard(at now: Date) -> some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 10) {
				Label { Text(tracking.status?.title(at: now) ?? "Waiting for Watch tracking status") } icon: { CiggyIconView(.watch, size: 20) }
					.font(.subheadline.weight(.bold))
					.foregroundStyle(palette.primaryText)
				Text(tracking.status?.detail(at: now) ?? "The Today screen shows your saved count. Ciggy requests recent motion from your paired Watch; today's total may still be incomplete until it responds.")
					.font(.caption)
					.foregroundStyle(palette.secondaryText)
				Button {
					ConnectivityManager.shared.requestHistoryRefresh()
				} label: {
					Label("Check Watch", systemImage: "arrow.clockwise")
						.font(.subheadline.weight(.semibold))
						.frame(minHeight: 44)
				}
				.buttonStyle(.plain)
				.foregroundStyle(palette.mint)
				.disabled(!HistoryRefreshPolicy.shouldRequest(at: now, lastRequestedAt: connectivity.lastHistoryRefreshRequestedAt))
				.accessibilityIdentifier("check-watch-history")
				if let requested = connectivity.lastHistoryRefreshRequestedAt,
				   now.timeIntervalSince(requested) < 60,
				   tracking.status?.historyCheckedAt.map({ $0 < requested }) ?? true {
					Text("Check requested. Your Watch can respond in the background when watchOS allows.")
						.font(.caption)
						.foregroundStyle(palette.secondaryText)
				}
			}
		}
	}

	private var heartRateCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Image(systemName: "heart.fill")
						.foregroundStyle(CiggyTheme.ember)
					Text("Heart-rate context")
						.font(.headline)
						.foregroundStyle(palette.primaryText)
					Spacer()
					Text("Optional")
						.font(.caption2.weight(.bold))
						.foregroundStyle(CiggyTheme.ember)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(CiggyTheme.ember.opacity(0.12), in: Capsule())
				}

				if viewModel.heartRateTrend.isEmpty {
					HStack(spacing: 12) {
						Image(systemName: "waveform.path.ecg")
							.font(.title2)
							.foregroundStyle(palette.secondaryText)
						Text("No heart-rate samples are attached to logged events yet.")
							.font(.subheadline)
							.foregroundStyle(palette.secondaryText)
					}
					.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
				} else {
					Chart(viewModel.heartRateTrend, id: \.0) { pair in
						LineMark(x: .value("Time", pair.0), y: .value("BPM", pair.1))
							.foregroundStyle(CiggyTheme.ember)
						PointMark(x: .value("Time", pair.0), y: .value("BPM", pair.1))
							.foregroundStyle(CiggyTheme.sunlight)
					}
					.frame(height: 190)
				}
			}
		}
	}

}
#endif
