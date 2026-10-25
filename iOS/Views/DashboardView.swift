#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

enum DashboardDestination: Hashable {
	case settings
}

struct DashboardView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@StateObject private var viewModel = DashboardViewModel()
	@ObservedObject private var connectivity = ConnectivityManager.shared
	@ObservedObject private var tracking = TrackingStatusStore.shared
	@State private var reviewToAdjust: DetectionReview?
	@State private var isLogging = false
	@State private var lastLoggedEvent: SmokingEvent?
	@State private var undoError: String?
	@State private var loggingNotes = ""
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	var body: some View {
		CiggyAdaptiveScreen(immersiveDuoDesk: true) {
			profileHeader
			CiggyDuoStatus()
			logConfirmation
			todayHero
			quickMetrics
			detectionExperience
			LiveActivityCard()
			weeklyChart
			todaysTimeline
		} overview: { mode in
			CiggyDuoDeskGate {
				CiggyDuoAshtrayScene()
			} normal: {
				profileHeader
				CiggyDuoStatus()
				if mode.isFolded {
					foldedSummary(mode: mode)
					if mode == .book { weeklyChart }
				} else {
					logConfirmation
					todayHero
					quickMetrics
				}
			}
		} controls: { mode in
			CiggyDuoDeskGate {
				CiggyDuoMusicPlayer()
			} normal: {
				if mode.isFolded {
					logConfirmation
					foldedCheckIn
					detectionStatus
					quickMetrics
					if mode == .tabletop { weeklyChart }
				} else {
					weeklyChart
					detectionExperience
				}
				todaysTimeline
				LiveActivityCard()
			}
		}

		.toolbar(.hidden, for: .navigationBar)
		.navigationDestination(for: DashboardDestination.self) { destination in
			switch destination {
			case .settings: SettingsView(showsNavigationBar: true)
			}
		}
		.onAppear { viewModel.bind(repository: repository, settings: settings) }
		.refreshable { ConnectivityManager.shared.requestHistoryRefresh() }
		.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Ciggy.widgetLogSaved"))) { notification in
			lastLoggedEvent = notification.object as? SmokingEvent
			undoError = nil
		}
		.sheet(isPresented: $isLogging) {
			PhoneLogSmokeView(notes: $loggingNotes) { event in
				lastLoggedEvent = event
				undoError = nil
			}
			.presentationDetents([.medium, .large])
			.presentationDragIndicator(.visible)
		}
		.sensoryFeedback(.success, trigger: lastLoggedEvent?.id)
		.sheet(item: $reviewToAdjust) { review in
			DetectionCountAdjustmentView(review: review) { correctedCount in
				DetectionReviewWorkflow.adjust(
					review,
					to: correctedCount,
					repository: repository,
					store: reviewStore
				)
			}
			.presentationDetents([.medium, .large])
		}
	}

	@ViewBuilder
	private var logConfirmation: some View {
		if let event = lastLoggedEvent {
			VStack(alignment: .leading, spacing: 8) {
				Label("Logged. No judgment.", systemImage: "checkmark.circle.fill")
				HStack {
					Button("Undo") {
						let removed = repository.removeEvent(id: event.id)
						if removed || repository.lastPersistenceError == nil {
							lastLoggedEvent = nil
							undoError = nil
						} else {
							undoError = repository.lastPersistenceError
						}
					}.fontWeight(.bold).accessibilityIdentifier("undo-phone-log")
						.frame(minHeight: 44)
					Spacer()
					Button { lastLoggedEvent = nil; undoError = nil } label: {
						Image(systemName: "xmark").frame(width: 44, height: 44)
					}.accessibilityLabel("Dismiss log confirmation")
				}
				if let undoError {
					Text(undoError).font(.caption)
						.accessibilityIdentifier("phone-undo-save-error")
				}
			}
			.font(.subheadline).padding(16)
			.ciggyGlass(in: RoundedRectangle(cornerRadius: 22))
			.foregroundStyle(palette.primaryText)
		}
	}

	private func foldedSummary(mode: CiggyLayoutPlan.Mode) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(mode == .tabletop ? "A little breathing room." : "Today's page.")
				.font(.system(.title2, design: .rounded, weight: .black))
			HStack {
				dailyCount
				Spacer(minLength: 0)
				if !dynamicTypeSize.isAccessibilitySize {
					CiggyMascot().frame(width: 88, height: 88)
				}
			}
			CiggyPackMeter(count: viewModel.dailyCount, limit: settings.settings.dailyLimit)
			Text(todayMessage).font(.subheadline.weight(.semibold))
		}
		.foregroundStyle(palette.primaryText)
		.padding(22)
		.background(palette.heroGradient, in: RoundedRectangle(cornerRadius: 28))
		.overlay(RoundedRectangle(cornerRadius: 28).stroke(palette.border, lineWidth: 1))
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier(mode == .tabletop ? "desk-summary" : "book-summary")
	}

	private var foldedCheckIn: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 8) {
				Text("Within reach.").font(.system(.title3, design: .rounded, weight: .bold))
				Text("Your Watch keeps track. Add a check-in here if it missed one.")
					.font(.caption).foregroundStyle(palette.secondaryText)
				manualLogButton
			}.foregroundStyle(palette.primaryText)
		}
	}

	private var todaysTimeline: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				Label { Text("Today's little moments") } icon: { CiggyIconView(.elapsed, size: 20) }
					.font(.headline).foregroundStyle(palette.primaryText)
				let events = repository.events.filter { Calendar.current.isDateInToday($0.timestamp) }.reversed()
				if events.isEmpty {
					Text("A fresh page. Your check-ins will appear here.")
						.font(.subheadline).foregroundStyle(palette.secondaryText)
				} else {
					ForEach(Array(events.prefix(8))) { event in
						HStack(alignment: .top, spacing: 12) {
							CiggyIconView(event.source == .manual ? .log : .watch, size: 20)
								.foregroundStyle(palette.mint)
							VStack(alignment: .leading, spacing: 3) {
								Text(event.source == .manual ? "You checked in" : "Watch detection")
									.font(.subheadline.weight(.semibold))
								if let notes = event.notes {
									Text(notes).font(.caption).foregroundStyle(palette.secondaryText)
								}
							}
							Spacer(minLength: 4)
							Text(event.timestamp, style: .time).font(.caption).foregroundStyle(palette.secondaryText)
						}.foregroundStyle(palette.primaryText)
					}
				}
			}
		}
	}

	private var profileHeader: some View {
		HStack(spacing: 10) {
			CiggyBrandMark(size: 38)
			Text("ciggy").font(.system(size: 33, weight: .black, design: .rounded)).tracking(-2)
				.foregroundStyle(palette.primaryText)
			Spacer()
			NavigationLink(value: DashboardDestination.settings) { CiggyProfileMark(size: 44) }
				.buttonStyle(.plain).accessibilityLabel("Open profile and settings")
				.accessibilityIdentifier("phone-profile-button")
		}
	}

	private var todayHero: some View {
		VStack(alignment: .leading, spacing: 18) {
			HStack {
				Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
					.textCase(.uppercase).tracking(1.5).font(.caption2.weight(.heavy))
				Spacer()
				Text("YOUR DAILY CHECK-IN").font(.system(size: 8, weight: .heavy)).tracking(1)
					.accessibilityHidden(true)
			}
			Text("Let's clear the air.")
				.font(.system(.largeTitle, design: .rounded, weight: .black)).tracking(-1.4)
			ViewThatFits(in: .horizontal) {
				heroCountRow
				VStack(alignment: .leading, spacing: 12) { dailyCount; CiggyMascot().frame(width: 160, height: 160).frame(maxWidth: .infinity) }
			}
			CiggyPackMeter(count: viewModel.dailyCount, limit: settings.settings.dailyLimit)
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					Text(todayMessage).font(.subheadline.weight(.bold))
					Text(viewModel.dailyCount == 0 ? "One day at a time. You've got this." : "Last logged \(viewModel.lastEventDescription.lowercased()).")
						.font(.caption).foregroundStyle(palette.secondaryText)
				}
				Spacer(minLength: 4)
				NavigationLink(destination: GoalsView(showsNavigationBar: true)) {
					Text("Limit \(settings.settings.dailyLimit)").font(.caption.weight(.bold))
						.padding(.horizontal, 12).padding(.vertical, 9).ciggyGlass(in: Capsule(), interactive: true)
				}.buttonStyle(.plain).accessibilityLabel("Edit daily limit, currently \(settings.settings.dailyLimit)")
			}
		}
		.foregroundStyle(palette.primaryText)
		.padding(22)
		.background(palette.heroGradient, in: RoundedRectangle(cornerRadius: 32))
		.overlay(RoundedRectangle(cornerRadius: 32).stroke(palette.border, lineWidth: 1))
		.shadow(color: CiggyTheme.ember.opacity(0.12), radius: 18, x: 0, y: 8)
	}

	private var heroCountRow: some View {
		HStack(alignment: .center, spacing: 0) {
			dailyCount.frame(minWidth: 130, alignment: .leading)
			Spacer(minLength: 0)
			CiggyMascot().frame(width: 156, height: 156)
		}
	}

	private var dailyCount: some View {
		VStack(alignment: .leading, spacing: -2) {
			Text("\(viewModel.dailyCount)")
				.font(.system(size: 76, weight: .black, design: .rounded)).tracking(-5)
				.contentTransition(.numericText())
				.animation(reduceMotion ? nil : .spring(response: 0.4), value: viewModel.dailyCount)
			Text("cigarettes today").font(.subheadline.weight(.semibold))
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(viewModel.dailyCount) cigarettes today")
		.accessibilityIdentifier("today-count")
	}

	private var quickMetrics: some View {
		LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 12) {
			metricCard(
				title: "Smoke-free",
				value: "\(viewModel.streakDays)d",
				icon: .streak,
				color: CiggyTheme.sunlight
			)
			metricCard(
				title: "This week",
				value: "\(viewModel.weeklyCount)",
				icon: .reports,
				color: CiggyTheme.lavender
			)
			metricCard(
				title: "Est. saved",
				value: String(format: "$%.0f", viewModel.moneySaved),
				icon: .savings,
				color: palette.mint
			)
		}
	}

	private var weeklyChart: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text("Your week, on paper")
							.font(.headline)
							.foregroundStyle(palette.primaryText)
						Text("Every log is a little more awareness.")
							.font(.caption)
							.foregroundStyle(palette.secondaryText)
					}
					Spacer()
					CiggyIconView(.reports, size: 22)
						.foregroundStyle(palette.mint)
				}

				Chart(ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)) { item in
					BarMark(
						x: .value("Day", item.date, unit: .day),
						y: .value("Count", item.count)
					)
					.foregroundStyle(CiggyTheme.emberGradient)
					.cornerRadius(6)
				}
				.frame(height: 170)
				.chartXAxis {
					AxisMarks(values: .stride(by: .day)) { _ in
						AxisValueLabel(format: .dateTime.weekday(.narrow))
							.foregroundStyle(palette.secondaryText)
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading) { _ in
						AxisGridLine().foregroundStyle(palette.border)
						AxisValueLabel().foregroundStyle(palette.secondaryText)
					}
				}
			}
		}
	}

	private var detectionExperience: some View {
		VStack(alignment: .leading, spacing: 2) {
			trackingFreshnessCard
			manualLogButton
			detectionReviews
		}
	}

	@ViewBuilder
	private var detectionStatus: some View {
		trackingFreshnessCard
		detectionReviews
	}

	@ViewBuilder
	private var detectionReviews: some View {
		if let error = reviewStore.lastPersistenceError {
			CiggyPanel {
				VStack(alignment: .leading, spacing: 10) {
					Text(error).font(.caption).foregroundStyle(palette.secondaryText)
					if reviewStore.pendingTransmissions.isEmpty == false {
						Button("Retry saved review") { _ = reviewStore.retryPendingCorrections() }
							.font(.subheadline.weight(.semibold))
					}
				}
				.accessibilityIdentifier("review-recovery-status")
			}
		}
		let todayReviews = reviewStore.reviews(on: Date())
		if todayReviews.isEmpty {
			detectionReadyCard
		}
		ForEach(todayReviews) { review in
			detectionReviewCard(review)
		}
		let earlier = reviewStore.previousReviews(before: Date())
		if earlier.isEmpty == false {
			DisclosureGroup("Earlier days") {
				ForEach(earlier) { review in
					detectionReviewCard(review)
				}
			}
			.font(.subheadline.weight(.semibold))
			.tint(palette.secondaryText)
			.accessibilityIdentifier("earlier-detection-reviews")
		}
	}

	private var trackingFreshnessCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 10) {
				Label { Text(tracking.status?.title() ?? "Waiting for Watch tracking status") } icon: { CiggyIconView(.watch, size: 20) }
					.font(.subheadline.weight(.bold))
					.foregroundStyle(palette.primaryText)
				Text(tracking.status?.detail() ?? "Your saved count is shown above. Ciggy requests recent motion from your paired Watch; today's total may still be incomplete until it responds.")
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
				.disabled(!HistoryRefreshPolicy.shouldRequest(at: Date(), lastRequestedAt: connectivity.lastHistoryRefreshRequestedAt))
				.accessibilityIdentifier("check-watch-history")
				if let requested = connectivity.lastHistoryRefreshRequestedAt,
				   Date().timeIntervalSince(requested) < 60,
				   tracking.status?.historyCheckedAt.map({ $0 < requested }) ?? true {
					Text("Check requested. Your Watch can respond in the background when watchOS allows.")
						.font(.caption)
						.foregroundStyle(palette.secondaryText)
				}
			}
		}
	}

	private var manualLogButton: some View {
		Button { isLogging = true } label: {
			Label { Text("Add missed cigarette") } icon: { CiggyIconView(.log, size: 20) }
				.font(.subheadline)
				.frame(minHeight: 44)
		}
		.buttonStyle(.plain)
		.foregroundStyle(palette.secondaryText)
		.accessibilityHint("Manually add one cigarette if detection missed it")
		.accessibilityIdentifier("phone-log-button")
	}

	private func detectionReviewCard(_ review: DetectionReview) -> some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				HStack(alignment: .top, spacing: 13) {
					Image(systemName: review.origin == .watchHistory ? "clock.arrow.circlepath" : "waveform.path.ecg")
						.font(.title3.weight(.bold))
						.foregroundStyle(CiggyTheme.deepInk)
						.frame(width: 44, height: 44)
						.background(CiggyTheme.brandGradient, in: Circle())
					VStack(alignment: .leading, spacing: 4) {
						Text("\(review.displayCount) \(review.displayCount == 1 ? "cigarette" : "cigarettes") detected\(Calendar.current.isDateInToday(review.windowStart) && Calendar.current.isDateInToday(review.windowEnd) ? " today" : "")")
							.font(.headline)
							.foregroundStyle(palette.primaryText)
						Text(reviewSummaryText(review))
							.font(.subheadline)
							.foregroundStyle(palette.secondaryText)
					}
					Spacer(minLength: 0)
				}

				if review.decision == .pending {
					Text("These detections are already included in your count. Confirm or correct this summary whenever you want.")
						.font(.caption)
						.foregroundStyle(palette.secondaryText)
					HStack(spacing: 10) {
						Button {
							DetectionReviewWorkflow.markAccurate(review, store: reviewStore)
						} label: {
							Label("Accurate", systemImage: "checkmark")
								.frame(maxWidth: .infinity)
								.padding(.vertical, 11)
								.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.foregroundStyle(CiggyTheme.deepInk)
						.buttonStyle(.plain)

						Button {
							reviewToAdjust = review
						} label: {
							Text("Adjust count")
								.frame(maxWidth: .infinity)
								.padding(.vertical, 11)
								.background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.foregroundStyle(palette.primaryText)
						.buttonStyle(.plain)
					}
					.font(.subheadline.weight(.bold))
				} else {
					Label(reviewDecisionText(review), systemImage: "checkmark.circle.fill")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(palette.mint)
				}
			}
		}
	}

	private var detectionReadyCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label { Text("Your little wrist sidekick") } icon: { CiggyIconView(.watch, size: 20) }
						.font(.subheadline.weight(.bold)).foregroundStyle(palette.primaryText)
					Spacer(minLength: 0)
				}
				CiggyStatusPill(syncStatusTitle, systemImage: connectivity.isLiveSyncAvailable ? "applewatch.radiowaves.left.and.right" : "arrow.triangle.2.circlepath", color: connectivity.isLiveSyncAvailable ? palette.mint : CiggyTheme.ember)
				Text("Wear your Watch on the hand you smoke with. Ciggy looks for repeated gestures; detection can miss cigarettes or mistake other movements. Review and adjust your total when needed.")
					.font(.caption).foregroundStyle(palette.secondaryText)
				Text("Today's count updates as recorded Watch motion is checked. The tracking status above shows how recent the available data is.")
					.font(.caption).foregroundStyle(palette.secondaryText)
			}
		}
	}

	private func reviewSummaryText(_ review: DetectionReview) -> String {
		let calendar = Calendar.current
		let day = calendar.isDateInToday(review.windowEnd) ? "Today" : review.windowEnd.formatted(date: .abbreviated, time: .omitted)
		if calendar.isDate(review.windowStart, inSameDayAs: review.windowEnd) {
			return "\(day) · \(review.windowStart.formatted(date: .omitted, time: .shortened)) – \(review.windowEnd.formatted(date: .omitted, time: .shortened))"
		}
		return "Earlier summary: \(review.windowStart.formatted(date: .abbreviated, time: .shortened)) – \(review.windowEnd.formatted(date: .abbreviated, time: .shortened))"
	}

	private func reviewDecisionText(_ review: DetectionReview) -> String {
		switch review.decision {
		case .pending:
			return ""
		case .accurate:
			return "Marked accurate · syncs with your paired Watch"
		case .adjusted:
			return "Count adjusted to \(review.displayCount) · syncs with your paired Watch"
		}
	}

	private func metricCard(title: String, value: String, icon: CiggyIcon, color: Color) -> some View {
		VStack(alignment: .leading, spacing: 9) {
			CiggyIconView(icon, size: 20)
				.foregroundStyle(color)
			Text(value)
				.font(.title2.weight(.black))
				.foregroundStyle(palette.primaryText)
			Text(title)
				.font(.caption2)
				.foregroundStyle(palette.secondaryText)
				.lineLimit(2)
		}
		.frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
		.padding(13)
		.background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(palette.border, lineWidth: 1)
		)
	}

	private var todayMessage: String {
		let remaining = max(0, settings.settings.dailyLimit - viewModel.dailyCount)
		if viewModel.dailyCount == 0 { return "A fresh page." }
		if remaining == 0 { return "Take a breather. Reset at your pace." }
		return "\(remaining) below your daily limit."
	}

	private var syncStatusTitle: String {
		if connectivity.isLiveSyncAvailable { return "Live sync" }
		if connectivity.isCounterpartAppInstalled == false { return "Install Watch" }
		#if targetEnvironment(simulator)
		return "Open Watch"
		#else
		return "Sync queued"
		#endif
	}
}

struct DashboardView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			DashboardView()
				.environmentObject(EventRepository())
				.environmentObject(UserSettingsStore())
				.environmentObject(DetectionReviewStore())
				.environmentObject(LiveActivityManager())
		}
	}
}

private struct DetectionCountAdjustmentView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	let review: DetectionReview
	let onSave: (Int) -> Bool
	@State private var count: Int
	@State private var saveFailed = false

	init(review: DetectionReview, onSave: @escaping (Int) -> Bool) {
		self.review = review
		self.onSave = onSave
		_count = State(initialValue: review.displayCount)
	}

	var body: some View {
		NavigationStack {
			ZStack {
				CiggyBackdrop()
				ScrollView {
					VStack(spacing: 22) {
						Text("How many cigarettes in this summary?")
							.font(.title2.weight(.black))
							.foregroundStyle(palette.primaryText)
							.multilineTextAlignment(.center)

						Stepper(value: $count, in: 0...100) {
							HStack {
								Text("Correct count")
								Spacer()
								Text("\(count)")
									.font(.title.weight(.black))
									.foregroundStyle(palette.mint)
									.accessibilityIdentifier("review-corrected-count")
							}
						}
						.padding()
						.background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
						.accessibilityIdentifier("review-count-stepper")
						.accessibilityValue("\(count)")

						Text("Corrects these detections on iPhone and Apple Watch, not your entire daily total. Times stay within this summary's date and window.")
							.font(.caption)
							.foregroundStyle(palette.secondaryText)
							.multilineTextAlignment(.center)

						if saveFailed {
							Text(reviewStore.lastPersistenceError ?? "Couldn't finish saving. Your count is still here; try again.")
								.font(.caption).foregroundStyle(palette.secondaryText)
								.accessibilityIdentifier("review-save-error")
						}

						Button(saveFailed ? "Retry corrected count" : "Save corrected count") {
							if onSave(count) { dismiss() }
							else { saveFailed = true }
						}
						.font(.headline)
						.foregroundStyle(CiggyTheme.deepInk)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 15)
						.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
						.buttonStyle(.plain)
						.accessibilityIdentifier("save-review-correction")
					}
					.padding(22)
				}
			}
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
		}
	}
}
#endif
