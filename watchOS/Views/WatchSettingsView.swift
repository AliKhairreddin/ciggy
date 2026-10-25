#if os(watchOS)
import CiggyShared
import SwiftUI

struct WatchSettingsView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settingsStore: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 10) {
				header
				watchCard { CiggyAppearanceSettings() }
				detectionCard
				goalCard
				summaryNotificationCard
				watchCard {
					VStack(alignment: .leading, spacing: 4) {
						Label("Motion calibration", systemImage: "waveform.path").font(.system(size: 11, weight: .bold))
						Text(settingsStore.settings.calibrationEnabledAt == nil ? "Sharing off. Pair and opt in from iPhone Settings to contribute recordings." : "Sharing enabled from iPhone. Recorded motion goes to the private dashboard via iPhone Wi-Fi; gaps and delays can occur.")
							.font(.system(size: 9)).foregroundStyle(palette.secondaryText)
					}
				}
				#if DEBUG
				previewCard
				#endif
                NavigationLink(destination: WatchTrackingDetailsView()) {
                    Label { Text("Tracking details") } icon: { CiggyIconView(.watch, size: 15) }
                }.accessibilityIdentifier("watch-tracking-details-link")
				Text("Detection and goal settings sync to your paired iPhone. Appearance stays on this Watch.")
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
					.multilineTextAlignment(.center)
					.frame(maxWidth: .infinity)
					.padding(.horizontal, 5)
			}
			.padding(.horizontal, 4)
			.padding(.bottom, 8)
		}
		.containerBackground(for: .navigation) { CiggyBackdrop() }
		.toolbarForegroundStyle(palette.primaryText, for: .navigationBar)
		.navigationTitle("Settings")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var header: some View {
		HStack(spacing: 9) {
			CiggyIconView(.settings, size: 20)
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(width: 36, height: 36)
				.background(CiggyTheme.brandGradient, in: Circle())
			VStack(alignment: .leading, spacing: 1) {
				Text("The control room")
					.font(.system(size: 17, weight: .black, design: .rounded))
					.foregroundStyle(palette.primaryText)
				Text("Small screen. Big clipboard.")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(palette.secondaryText)
			}
			Spacer(minLength: 0)
		}
	}

	private var detectionCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 9) {
				HStack {
					Label { Text("Sensitivity") } icon: { CiggyIconView(.watch, size: 15) }
					Spacer()
					Text(sensitivityName)
						.foregroundStyle(palette.mint)
				}
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(palette.primaryText)

				Slider(
					value: sensitivityBinding,
					in: 0...1,
					step: 0.1,
					minimumValueLabel: Image(systemName: "tortoise.fill"),
					maximumValueLabel: Image(systemName: "hare.fill")
				) {
					Text("Motion sensitivity")
				}
				.tint(palette.mint)
				.accessibilityValue(sensitivityName)

				Text(sensitivityDescription)
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
			}
		}
	}

	private var goalCard: some View {
		watchCard {
			Stepper(value: dailyLimitBinding, in: 1...100) {
				HStack {
					Label { Text("Daily limit") } icon: { CiggyIconView(.limit, size: 15) }
					Spacer()
					Text("\(settingsStore.settings.dailyLimit)")
						.font(.system(size: 18, weight: .black, design: .rounded))
						.foregroundStyle(palette.mint)
				}
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(palette.primaryText)
			}
		}
	}

	private var summaryNotificationCard: some View {
		watchCard {
			Toggle(isOn: notificationsBinding) {
				VStack(alignment: .leading, spacing: 2) {
					Label("Roasts & summaries", systemImage: "bell.badge.fill")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(palette.primaryText)
					Text("Daily roasts on iPhone + Watch history")
						.font(.system(size: 9))
						.foregroundStyle(palette.secondaryText)
				}
			}
			.tint(palette.mint)
		}
	}

	#if DEBUG
	private var previewCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 8) {
				Label("Try history summary", systemImage: "sparkles")
					.font(.system(size: 11, weight: .bold))
					.foregroundStyle(palette.primaryText)
				Text("Creates 6 debug detections over 8 hours and syncs them.")
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
				Button("Preview 6 detected") {
					DetectionReviewWorkflow.createHistoricalPreview(
						repository: repository,
						store: reviewStore
					)
				}
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
				.buttonStyle(.plain)
			}
		}
	}
	#endif

	private func watchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
		content()
			.padding(10)
			.background(palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 15, style: .continuous)
					.stroke(palette.border, lineWidth: 1)
			)
	}

	private var sensitivityBinding: Binding<Double> {
		Binding(
			get: { settingsStore.settings.sensitivity },
			set: { value in updateSettings { $0.sensitivity = value } }
		)
	}

	private var dailyLimitBinding: Binding<Int> {
		Binding(
			get: { settingsStore.settings.dailyLimit },
			set: { value in updateSettings { $0.dailyLimit = value } }
		)
	}

	private var notificationsBinding: Binding<Bool> {
		Binding(
			get: { settingsStore.settings.notificationsEnabled },
			set: { value in updateSettings { $0.notificationsEnabled = value } }
		)
	}

	private func updateSettings(_ update: (inout UserSettings) -> Void) {
		var updated = settingsStore.settings
		update(&updated)
		guard updated != settingsStore.settings else { return }
		settingsStore.settings = updated
		ConnectivityManager.shared.send(settings: updated)
	}

	private var sensitivityName: String {
		switch settingsStore.settings.sensitivity {
		case ..<0.34: return "Conservative"
		case 0.67...: return "Responsive"
		default: return "Balanced"
		}
	}

	private var sensitivityDescription: String {
		switch settingsStore.settings.sensitivity {
			case ..<0.34: return "At least seven matching movements over about five minutes per estimate."
			case 0.67...: return "At least four matching movements over about five minutes; more false detections possible."
			default: return "At least five matching movements over about five minutes per estimate. Continued motion can add another; short cigarettes may be missed and long ones split."
		}
	}


}

struct WatchSettingsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			WatchSettingsView()
				.environmentObject(EventRepository())
				.environmentObject(UserSettingsStore())
				.environmentObject(DetectionReviewStore())
		}
	}
}
struct WatchTrackingDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: WatchAppCoordinator
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @ObservedObject private var motion = MotionManager.shared
    @ObservedObject private var backgroundMotion = BackgroundMotionMonitor.shared
    @ObservedObject private var health = HealthKitManager.shared
    @ObservedObject private var tracking = TrackingStatusStore.shared
    private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                watchCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tracking.status?.title() ?? "Waiting for tracking status")
                            .font(.headline)
                        Text(tracking.status?.detail() ?? "Open Ciggy to check recorded movement.")
                            .font(.caption)
                        Button("Check now") { Task { await coordinator.refreshTracking() } }
                            .disabled(backgroundMotion.isProcessingHistory)
                            .accessibilityIdentifier("watch-check-history")
                    }.foregroundStyle(palette.primaryText)
                }
                diagnosticsCard
            }.padding(.horizontal, 4)
        }
        .navigationTitle("Tracking details")
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(for: .navigation) { CiggyBackdrop() }
        .toolbarForegroundStyle(palette.primaryText, for: .navigationBar)
    }

	private var diagnosticsCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 9) {
				Text("STATUS")
					.font(.system(size: 9, weight: .black))
					.tracking(0.7)
					.foregroundStyle(palette.secondaryText)
				diagnosticRow(
					icon: "hand.raised.fingers.spread.fill",
					title: "Live motion",
					detail: motion.isMonitoring ? "Listening" : "Paused",
					color: motion.isMonitoring ? palette.mint : CiggyTheme.sunlight
				)
				diagnosticRow(
					icon: "clock.arrow.circlepath",
					title: "Background",
					detail: backgroundMotion.statusText,
					color: backgroundMotion.isCaptureArmed ? palette.mint : CiggyTheme.ember
				)
				diagnosticRow(
					icon: "iphone.radiowaves.left.and.right",
					title: "iPhone",
					detail: connectionDetail,
					color: connectivity.isLiveSyncAvailable ? palette.mint : CiggyTheme.sunlight
				)
				diagnosticRow(
					icon: "heart.fill",
					title: "Heart rate",
					detail: heartRateDetail,
					color: CiggyTheme.lavender
				)

				Text(backgroundMotion.statusDetail)
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
				Text("Motion is an estimate. Wear this Watch on the hand you smoke with. Counts can appear later; open Ciggy to check recent movement. Heart rate is optional.")
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
				Text("For more background opportunities, keep a Ciggy complication on your active Watch face. Opening the iPhone also requests a motion check.")
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
			}
		}
	}

	private func watchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
		content()
			.padding(10)
			.background(palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 15, style: .continuous)
					.stroke(palette.border, lineWidth: 1)
			)
	}

	private func diagnosticRow(icon: String, title: String, detail: String, color: Color) -> some View {
		HStack(spacing: 7) {
			Image(systemName: icon)
				.foregroundStyle(color)
				.frame(width: 15)
			Text(title)
				.foregroundStyle(palette.primaryText)
			Spacer(minLength: 2)
			Text(detail)
				.foregroundStyle(palette.secondaryText)
		}
		.font(.system(size: 10, weight: .semibold))
	}

	private var connectionDetail: String {
		if connectivity.isLiveSyncAvailable { return "Live sync" }
		if connectivity.isActivated == false { return "Starting…" }
		if connectivity.isCounterpartAppInstalled == false { return "Open iPhone" }
		return "Waiting"
	}

	private var heartRateDetail: String {
		guard health.currentHeartRate.isFinite, (1...300).contains(health.currentHeartRate) else { return "Optional" }
		let suffix = health.isUsingSimulatedData ? " demo" : " BPM"
		return "\(Int(health.currentHeartRate))\(suffix)"
	}
}

#endif
