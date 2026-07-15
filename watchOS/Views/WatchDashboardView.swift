#if os(watchOS)
import CiggyShared
import SwiftUI

struct WatchDashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var feedbackStore: DetectionFeedbackStore
	@EnvironmentObject private var candidateStore: DetectionCandidateStore
	@EnvironmentObject private var coordinator: WatchAppCoordinator
	@StateObject private var viewModel = WatchDashboardViewModel()
	@ObservedObject private var connectivity = ConnectivityManager.shared
	@ObservedObject private var backgroundMotion = BackgroundMotionMonitor.shared

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(spacing: 10) {
					brandHeader
					todayRing
					motionStatus
					syncStatus
					logButton
					weeklyLink
				}
				.padding(.horizontal, 4)
				.padding(.bottom, 8)
			}
		}
		.onAppear { viewModel.bind(repository: repository) }
		.sheet(isPresented: candidateIsPresented) {
			if let candidate = candidateStore.pendingCandidate {
				DetectionConfirmationView(
					candidate: candidate,
					pendingCount: candidateStore.pendingCount,
					onConfirm: {
						coordinator.confirm(
							candidate,
							repository: repository,
							feedbackStore: feedbackStore,
							candidateStore: candidateStore
						)
					},
					onDismiss: {
						coordinator.dismiss(
							candidate,
							feedbackStore: feedbackStore,
							candidateStore: candidateStore
						)
					}
				)
			}
		}
	}

	private var brandHeader: some View {
		HStack(spacing: 7) {
			CiggyBrandMark(size: 28)
			Text("ciggy")
				.font(.system(size: 20, weight: .black, design: .rounded))
				.foregroundStyle(.white)
			Spacer()
			Circle()
				.fill(isMotionMonitoring ? CiggyTheme.mint : CiggyTheme.ember)
				.frame(width: 7, height: 7)
				.shadow(color: isMotionMonitoring ? CiggyTheme.mint : CiggyTheme.ember, radius: 4)
			NavigationLink(destination: WatchSettingsView()) {
				Image(systemName: "gearshape.fill")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 30, height: 30)
					.background(CiggyTheme.elevatedSurface, in: Circle())
					.overlay(Circle().stroke(CiggyTheme.border, lineWidth: 1))
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
				.stroke(CiggyTheme.elevatedSurface, lineWidth: 11)
			Circle()
				.trim(from: 0, to: max(0.025, todayProgress))
				.stroke(
					todayProgress >= 1 ? CiggyTheme.emberGradient : CiggyTheme.brandGradient,
					style: StrokeStyle(lineWidth: 11, lineCap: .round)
				)
				.rotationEffect(.degrees(-90))
			VStack(spacing: -1) {
				Text("\(viewModel.todayCount)")
					.font(.system(size: 38, weight: .black, design: .rounded))
					.foregroundStyle(.white)
				Text("TODAY · \(settings.settings.dailyLimit) LIMIT")
					.font(.system(size: 8, weight: .bold))
					.tracking(0.6)
					.foregroundStyle(CiggyTheme.secondaryText)
				if candidateStore.pendingCount > 0 {
					Text("+\(candidateStore.pendingCount) POSSIBLE")
						.font(.system(size: 7, weight: .black))
						.tracking(0.5)
						.foregroundStyle(CiggyTheme.sunlight)
				}
			}
		}
		.frame(width: 126, height: 126)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(todayAccessibilityLabel)
	}

	private var motionStatus: some View {
		HStack(spacing: 9) {
			Image(systemName: isMotionMonitoring ? "hand.raised.fingers.spread.fill" : "exclamationmark.triangle.fill")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(isMotionMonitoring ? CiggyTheme.mint : CiggyTheme.ember)
			VStack(alignment: .leading, spacing: 1) {
				Text(isMotionMonitoring ? "Motion monitoring" : "Motion unavailable")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(.white)
				Text(sensorDetail)
					.font(.system(size: 9))
					.foregroundStyle(CiggyTheme.secondaryText)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 15, style: .continuous)
				.stroke(CiggyTheme.border, lineWidth: 1)
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
				.foregroundStyle(connectivity.isLiveSyncAvailable ? CiggyTheme.mint : CiggyTheme.sunlight)
			Text(syncStatusText)
			Spacer(minLength: 0)
		}
		.font(.system(size: 10, weight: .semibold))
		.foregroundStyle(CiggyTheme.secondaryText)
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
			.foregroundStyle(.white)
			.padding(.horizontal, 10)
		}
		.buttonStyle(.plain)
	}

	private var todayProgress: Double {
		min(1, Double(viewModel.todayCount) / Double(max(1, settings.settings.dailyLimit)))
	}

	private var todayAccessibilityLabel: String {
		let base = "\(viewModel.todayCount) confirmed cigarettes today, daily limit \(settings.settings.dailyLimit)"
		guard candidateStore.pendingCount > 0 else { return base }
		return "\(base), \(candidateStore.pendingCount) possible events awaiting review"
	}

	private var sensorDetail: String {
		if backgroundMotion.isProcessingHistory {
			return "Checking recorded background movement"
		}
		if candidateStore.pendingCount > 0 {
			return "\(candidateStore.pendingCount) possible awaiting review"
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

	private var candidateIsPresented: Binding<Bool> {
		Binding(
			get: { candidateStore.pendingCandidate != nil },
			set: { _ in }
		)
	}
}

struct WatchDashboardView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			WatchDashboardView()
				.environmentObject(EventRepository())
				.environmentObject(UserSettingsStore())
				.environmentObject(DetectionFeedbackStore())
				.environmentObject(DetectionCandidateStore())
				.environmentObject(WatchAppCoordinator())
		}
	}
}
#endif
