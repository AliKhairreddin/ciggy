#if os(watchOS)
import CiggyShared
import SwiftUI

struct WatchSettingsView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settingsStore: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@ObservedObject private var connectivity = ConnectivityManager.shared
	@ObservedObject private var motion = MotionManager.shared
	@ObservedObject private var backgroundMotion = BackgroundMotionMonitor.shared
	@ObservedObject private var health = HealthKitManager.shared

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 10) {
					header
					detectionCard
					goalCard
					summaryNotificationCard
					#if DEBUG
					previewCard
					#endif
					diagnosticsCard
					Text("Changes save on this Watch and sync to the paired iPhone automatically.")
						.font(.system(size: 9))
						.foregroundStyle(CiggyTheme.secondaryText)
						.multilineTextAlignment(.center)
						.frame(maxWidth: .infinity)
						.padding(.horizontal, 5)
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 8)
			}
		}
		.navigationTitle("Settings")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var header: some View {
		HStack(spacing: 9) {
			Image(systemName: "slider.horizontal.3")
				.font(.system(size: 16, weight: .bold))
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(width: 36, height: 36)
				.background(CiggyTheme.brandGradient, in: Circle())
			VStack(alignment: .leading, spacing: 1) {
				Text("Tune Ciggy")
					.font(.system(size: 17, weight: .black, design: .rounded))
					.foregroundStyle(.white)
				Text("Motion-first controls")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(CiggyTheme.secondaryText)
			}
			Spacer(minLength: 0)
		}
	}

	private var detectionCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 9) {
				HStack {
					Label("Sensitivity", systemImage: "hand.raised.fingers.spread.fill")
					Spacer()
					Text(sensitivityName)
						.foregroundStyle(CiggyTheme.mint)
				}
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(.white)

				Slider(
					value: sensitivityBinding,
					in: 0...1,
					step: 0.1,
					minimumValueLabel: Image(systemName: "tortoise.fill"),
					maximumValueLabel: Image(systemName: "hare.fill")
				) {
					Text("Motion sensitivity")
				}
				.tint(CiggyTheme.mint)
				.accessibilityValue(sensitivityName)

				Text(sensitivityDescription)
					.font(.system(size: 9))
					.foregroundStyle(CiggyTheme.secondaryText)
			}
		}
	}

	private var goalCard: some View {
		watchCard {
			Stepper(value: dailyLimitBinding, in: 1...100) {
				HStack {
					Label("Daily limit", systemImage: "scope")
					Spacer()
					Text("\(settingsStore.settings.dailyLimit)")
						.font(.system(size: 18, weight: .black, design: .rounded))
						.foregroundStyle(CiggyTheme.mint)
				}
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(.white)
			}
		}
	}

	private var summaryNotificationCard: some View {
		watchCard {
			Toggle(isOn: notificationsBinding) {
				VStack(alignment: .leading, spacing: 2) {
					Label("Detection summaries", systemImage: "bell.badge.fill")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.white)
					Text("Notify after history is checked")
						.font(.system(size: 9))
						.foregroundStyle(CiggyTheme.secondaryText)
				}
			}
			.tint(CiggyTheme.mint)
		}
	}

	#if DEBUG
	private var previewCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 8) {
				Label("Try history summary", systemImage: "sparkles")
					.font(.system(size: 11, weight: .bold))
					.foregroundStyle(.white)
				Text("Creates 6 debug detections over 8 hours and syncs them.")
					.font(.system(size: 9))
					.foregroundStyle(CiggyTheme.secondaryText)
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

	private var diagnosticsCard: some View {
		watchCard {
			VStack(alignment: .leading, spacing: 9) {
				Text("STATUS")
					.font(.system(size: 9, weight: .black))
					.tracking(0.7)
					.foregroundStyle(CiggyTheme.secondaryText)
				diagnosticRow(
					icon: "hand.raised.fingers.spread.fill",
					title: "Live motion",
					detail: motion.isMonitoring ? "Listening" : "Paused",
					color: motion.isMonitoring ? CiggyTheme.mint : CiggyTheme.sunlight
				)
				diagnosticRow(
					icon: "clock.arrow.circlepath",
					title: "Background",
					detail: backgroundMotion.statusText,
					color: backgroundMotion.isCaptureArmed ? CiggyTheme.mint : CiggyTheme.ember
				)
				diagnosticRow(
					icon: "iphone.radiowaves.left.and.right",
					title: "iPhone",
					detail: connectionDetail,
					color: connectivity.isLiveSyncAvailable ? CiggyTheme.mint : CiggyTheme.sunlight
				)
				diagnosticRow(
					icon: "heart.fill",
					title: "Heart rate",
					detail: heartRateDetail,
					color: CiggyTheme.lavender
				)

				Text("Background movement is checked when Ciggy wakes. Heart rate remains optional context.")
					.font(.system(size: 9))
					.foregroundStyle(CiggyTheme.secondaryText)
			}
		}
	}

	private func watchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
		content()
			.padding(10)
			.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 15, style: .continuous)
					.stroke(CiggyTheme.border, lineWidth: 1)
			)
	}

	private func diagnosticRow(icon: String, title: String, detail: String, color: Color) -> some View {
		HStack(spacing: 7) {
			Image(systemName: icon)
				.foregroundStyle(color)
				.frame(width: 15)
			Text(title)
				.foregroundStyle(.white)
			Spacer(minLength: 2)
			Text(detail)
				.foregroundStyle(CiggyTheme.secondaryText)
		}
		.font(.system(size: 10, weight: .semibold))
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
		case ..<0.34: return "Waits for more matching movements before detecting."
		case 0.67...: return "Detects sooner, with a greater chance of false detections."
		default: return "Balances earlier detections with fewer false alarms."
		}
	}

	private var connectionDetail: String {
		if connectivity.isLiveSyncAvailable { return "Live sync" }
		if connectivity.isActivated == false { return "Starting…" }
		if connectivity.isCounterpartAppInstalled == false { return "Open iPhone" }
		return "Waiting"
	}

	private var heartRateDetail: String {
		guard health.currentHeartRate > 0 else { return "Optional" }
		let suffix = health.isUsingSimulatedData ? " demo" : " BPM"
		return "\(Int(health.currentHeartRate))\(suffix)"
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
#endif
