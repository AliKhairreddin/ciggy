#if os(watchOS)
import CiggyShared
import SwiftUI

struct WatchDashboardView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@StateObject private var viewModel = WatchDashboardViewModel()
	@ObservedObject private var connectivity = ConnectivityManager.shared
	@ObservedObject private var backgroundMotion = BackgroundMotionMonitor.shared
	@State private var reviewToAdjust: DetectionReview?
	@State private var widgetDestination: String?

	var body: some View {
		ZStack {
			CiggyBackdrop()
			ScrollView {
				VStack(spacing: 10) {
					profileHeader
					todayRing
					logButton
					if let review = reviewStore.latestReview {
						detectionReviewCard(review)
					}
					motionStatus
					syncStatus
					weeklyLink
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 8)
			}
		}
		.onAppear { viewModel.bind(repository: repository) }
		.onOpenURL { url in
			guard url.scheme == "ciggy" else { return }
			if ["log", "reports", "goals"].contains(url.host ?? "") { widgetDestination = url.host }
		}
		.navigationDestination(item: $widgetDestination) { destination in
			switch destination {
			case "log": LogSmokeView()
			case "reports": WeeklySummaryView()
			default: WatchSettingsView()
			}
		}
		.sheet(item: $reviewToAdjust) { review in
			WatchDetectionCountAdjustmentView(review: review) { correctedCount in
				DetectionReviewWorkflow.adjust(
					review,
					to: correctedCount,
					repository: repository,
					store: reviewStore
				)
			}
		}
	}

	private var profileHeader: some View {
		HStack(spacing: 7) {
			NavigationLink(destination: WatchSettingsView()) {
				CiggyProfileMark(size: 30)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open profile and settings")
			Text("ciggy").font(.system(size: 20, weight: .black, design: .rounded)).tracking(-1).foregroundStyle(palette.primaryText)
			Spacer()
			Circle()
				.fill(isMotionMonitoring ? palette.mint : CiggyTheme.ember)
				.frame(width: 7, height: 7)
				.shadow(color: isMotionMonitoring ? palette.mint : CiggyTheme.ember, radius: 4)
			NavigationLink(destination: WatchSettingsView()) {
				Image(systemName: "gearshape.fill")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(palette.primaryText)
					.frame(width: 30, height: 30)
					.background(palette.elevatedSurface, in: Circle())
					.overlay(Circle().stroke(palette.border, lineWidth: 1))
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Settings")
			.accessibilityIdentifier("watch-settings-button")
		}
		.padding(.horizontal, 2)
	}

	private var todayRing: some View {
		ZStack {
			Circle()
				.stroke(palette.elevatedSurface, lineWidth: 11)
			Circle()
				.trim(from: 0, to: max(0.025, todayProgress))
				.stroke(
					todayProgress >= 1 ? CiggyTheme.emberGradient : CiggyTheme.brandGradient,
					style: StrokeStyle(lineWidth: 11, lineCap: .round)
				)
				.rotationEffect(.degrees(-90))
			CiggyMascot(animated: false).frame(width: 58, height: 58).offset(x: 43, y: 36)
			VStack(spacing: -1) {
				Text("\(viewModel.todayCount)")
					.contentTransition(.numericText())
					.font(.system(size: 38, weight: .black, design: .rounded))
					.foregroundStyle(palette.primaryText)
				Text("TODAY · \(settings.settings.dailyLimit) LIMIT")
					.font(.system(size: 8, weight: .bold))
					.tracking(0.6)
					.foregroundStyle(palette.secondaryText)
			}
		}
		.frame(width: 126, height: 126)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(todayAccessibilityLabel)
	}

	private func detectionReviewCard(_ review: DetectionReview) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Image(systemName: review.origin == .watchHistory ? "clock.arrow.circlepath" : "waveform.path.ecg")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(CiggyTheme.deepInk)
					.frame(width: 30, height: 30)
					.background(CiggyTheme.brandGradient, in: Circle())
				VStack(alignment: .leading, spacing: 1) {
					Text("\(review.displayCount) detected")
						.font(.system(size: 14, weight: .black, design: .rounded))
						.foregroundStyle(palette.primaryText)
					Text(review.origin == .watchHistory ? "Last \(review.historyHours)h of Watch history" : "While monitoring motion")
						.font(.system(size: 8))
						.foregroundStyle(palette.secondaryText)
				}
				Spacer(minLength: 0)
			}

			if review.decision == .pending {
				Text("Already added. Feedback is optional.")
					.font(.system(size: 8))
					.foregroundStyle(palette.secondaryText)
				HStack(spacing: 6) {
					Button("Accurate") {
						DetectionReviewWorkflow.markAccurate(review, store: reviewStore)
					}
					.foregroundStyle(CiggyTheme.deepInk)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 7)
					.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

					Button("Adjust") { reviewToAdjust = review }
						.foregroundStyle(palette.primaryText)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 7)
						.background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
				}
				.buttonStyle(.plain)
				.font(.system(size: 10, weight: .bold))
			} else {
				Label(
					review.decision == .accurate ? "Marked accurate" : "Adjusted to \(review.displayCount)",
					systemImage: "checkmark.circle.fill"
				)
				.font(.system(size: 9, weight: .semibold))
				.foregroundStyle(palette.mint)
			}
		}
		.padding(10)
		.background(palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 15, style: .continuous)
				.stroke(palette.mint.opacity(0.22), lineWidth: 1)
		)
	}

	private var motionStatus: some View {
		HStack(spacing: 9) {
			Image(systemName: isMotionMonitoring ? "hand.raised.fingers.spread.fill" : "exclamationmark.triangle.fill")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(isMotionMonitoring ? palette.mint : CiggyTheme.ember)
			VStack(alignment: .leading, spacing: 1) {
				Text(isMotionMonitoring ? "Motion monitoring" : "Motion unavailable")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(palette.primaryText)
				Text(sensorDetail)
					.font(.system(size: 9))
					.foregroundStyle(palette.secondaryText)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.background(palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 15, style: .continuous)
				.stroke(palette.border, lineWidth: 1)
		)
	}

	private var logButton: some View {
		NavigationLink(destination: LogSmokeView()) {
			Label("Log 1 cigarette", systemImage: "plus")
				.font(.system(size: 14, weight: .bold))
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 12)
				.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
		.buttonStyle(.plain)
	}

	private var syncStatus: some View {
		HStack(spacing: 7) {
			Image(systemName: connectivity.isLiveSyncAvailable ? "iphone.radiowaves.left.and.right" : "arrow.triangle.2.circlepath")
				.foregroundStyle(connectivity.isLiveSyncAvailable ? palette.mint : CiggyTheme.sunlight)
			Text(syncStatusText)
			Spacer(minLength: 0)
		}
		.font(.system(size: 10, weight: .semibold))
		.foregroundStyle(palette.secondaryText)
		.padding(.horizontal, 8)
		.accessibilityElement(children: .combine)
	}

	private var weeklyLink: some View {
		NavigationLink(destination: WeeklySummaryView()) {
			HStack {
				Image(systemName: "chart.bar.fill")
				Text("7-day rhythm")
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.bold))
			}
			.font(.system(size: 12, weight: .semibold))
			.foregroundStyle(palette.primaryText)
			.padding(.horizontal, 10)
		}
		.buttonStyle(.plain)
	}

	private var todayProgress: Double {
		min(1, Double(viewModel.todayCount) / Double(max(1, settings.settings.dailyLimit)))
	}

	private var todayAccessibilityLabel: String {
		"\(viewModel.todayCount) cigarettes today, daily limit \(settings.settings.dailyLimit)"
	}

	private var sensorDetail: String {
		if backgroundMotion.isProcessingHistory {
			return "Checking recorded background movement"
		}
		if viewModel.currentHeartRate > 0 {
			let simulated = viewModel.isUsingSimulatedHeartRate ? " · demo" : ""
			let background = backgroundMotion.isCaptureArmed ? " · background armed" : ""
			return "\(Int(viewModel.currentHeartRate)) BPM\(simulated)\(background)"
		}
		return backgroundMotion.isCaptureArmed ? "Live now · background armed" : "Looking for repeated gestures"
	}

	private var isMotionMonitoring: Bool {
		viewModel.isMotionMonitoring || backgroundMotion.isCaptureArmed
	}

	private var syncStatusText: String {
		if connectivity.isLiveSyncAvailable { return "iPhone live" }
		if connectivity.isCounterpartAppInstalled == false { return "Install iPhone app" }
		#if targetEnvironment(simulator)
		return "Open iPhone to sync"
		#else
		return "Will sync when available"
		#endif
	}

}

struct WatchDashboardView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			WatchDashboardView()
				.environmentObject(EventRepository())
				.environmentObject(UserSettingsStore())
				.environmentObject(DetectionReviewStore())
		}
	}
}

private struct WatchDetectionCountAdjustmentView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.dismiss) private var dismiss
	let review: DetectionReview
	let onSave: (Int) -> Void
	@State private var count: Int

	init(review: DetectionReview, onSave: @escaping (Int) -> Void) {
		self.review = review
		self.onSave = onSave
		_count = State(initialValue: review.displayCount)
	}

	var body: some View {
		ZStack {
			CiggyBackdrop()
			ScrollView {
				VStack(spacing: 10) {
					Text("Correct count")
						.font(.system(size: 18, weight: .black, design: .rounded))
						.foregroundStyle(palette.primaryText)
					Stepper(value: $count, in: 0...100) {
						Text("\(count)")
							.font(.system(size: 28, weight: .black, design: .rounded))
							.foregroundStyle(palette.mint)
					}
					.padding(9)
					.background(palette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
					Text("Updates both devices")
						.font(.system(size: 9))
						.foregroundStyle(palette.secondaryText)
					Button("Save") {
						onSave(count)
						dismiss()
					}
					.font(.headline)
					.foregroundStyle(CiggyTheme.deepInk)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 9)
					.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
					.buttonStyle(.plain)
					Button("Cancel") { dismiss() }
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(palette.secondaryText)
						.buttonStyle(.plain)
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 6)
			}
		}
	}
}
#endif
