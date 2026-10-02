#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

struct DashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@StateObject private var viewModel = DashboardViewModel()
	@ObservedObject private var connectivity = ConnectivityManager.shared
	@State private var reviewToAdjust: DetectionReview?
	@State private var isLogging = false
	@State private var lastLoggedEvent: SmokingEvent?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			CiggyBackdrop()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					profileHeader
					todayHero
					quickMetrics
					detectionExperience
					weeklyChart
				}
				.padding(.horizontal, 18)
				.padding(.top, 14)
				.padding(.bottom, 28)
			}
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository, settings: settings) }
		.sheet(isPresented: $isLogging) {
			PhoneLogSmokeView { event in
				lastLoggedEvent = event
			}
			.presentationDetents([.medium, .large])
			.presentationDragIndicator(.visible)
		}
		.sensoryFeedback(.success, trigger: lastLoggedEvent?.id)
		.safeAreaInset(edge: .bottom) {
			if let event = lastLoggedEvent {
				HStack {
					Label("Logged. No judgment.", systemImage: "checkmark.circle.fill")
					Spacer()
					Button("Undo") {
						repository.removeEvent(id: event.id)
						ConnectivityManager.shared.sendDeletedEvent(id: event.id)
						lastLoggedEvent = nil
					}.fontWeight(.bold).accessibilityIdentifier("undo-phone-log")
					Button { lastLoggedEvent = nil } label: { Image(systemName: "xmark") }
						.accessibilityLabel("Dismiss log confirmation")
				}
				.font(.subheadline).padding(16)
				.ciggyGlass(in: RoundedRectangle(cornerRadius: 22))
				.padding(.horizontal, 18).padding(.bottom, 8)
				.foregroundStyle(CiggyTheme.ink)
			}
		}
		.sheet(item: $reviewToAdjust) { review in
			DetectionCountAdjustmentView(review: review) { correctedCount in
				DetectionReviewWorkflow.adjust(
					review,
					to: correctedCount,
					repository: repository,
					store: reviewStore
				)
			}
			.presentationDetents([.medium])
		}
	}

	private var profileHeader: some View {
		HStack(spacing: 10) {
			CiggyBrandMark(size: 38)
			Text("ciggy").font(.system(size: 33, weight: .black, design: .rounded)).tracking(-2)
				.foregroundStyle(CiggyTheme.ink)
			Spacer()
			NavigationLink(destination: SettingsView(showsNavigationBar: true)) { CiggyProfileMark(size: 44) }
				.buttonStyle(.plain).accessibilityLabel("Open profile and settings")
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
						.font(.caption).foregroundStyle(CiggyTheme.ink.opacity(0.7))
				}
				Spacer(minLength: 4)
				NavigationLink(destination: GoalsView(showsNavigationBar: true)) {
					Text("Limit \(settings.settings.dailyLimit)").font(.caption.weight(.bold))
						.padding(.horizontal, 12).padding(.vertical, 9).ciggyGlass(in: Capsule(), interactive: true)
				}.buttonStyle(.plain).accessibilityLabel("Edit daily limit, currently \(settings.settings.dailyLimit)")
			}
			Button { isLogging = true } label: {
				HStack {
					Image(systemName: "plus").font(.title3.weight(.semibold))
					Text("Log a cigarette").font(.headline)
					Spacer()
					Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
				}.padding(17).frame(maxWidth: .infinity)
					.ciggyGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
			}.buttonStyle(.plain).accessibilityIdentifier("phone-log-button")
		}
		.foregroundStyle(CiggyTheme.ink)
		.padding(22)
		.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 32))
		.overlay(RoundedRectangle(cornerRadius: 32).stroke(CiggyTheme.ink.opacity(0.18), lineWidth: 1))
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
		HStack(spacing: 12) {
			metricCard(
				title: "Smoke-free",
				value: "\(viewModel.streakDays)d",
				icon: "sparkles",
				color: CiggyTheme.sunlight
			)
			metricCard(
				title: "This week",
				value: "\(viewModel.weeklyCount)",
				icon: "calendar",
				color: CiggyTheme.lavender
			)
			metricCard(
				title: "Est. saved",
				value: String(format: "$%.0f", viewModel.moneySaved),
				icon: "leaf.fill",
				color: CiggyTheme.mint
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
							.foregroundStyle(CiggyTheme.primaryText)
						Text("Every log is a little more awareness.")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer()
					Image(systemName: "chart.bar.xaxis")
						.foregroundStyle(CiggyTheme.mint)
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
							.foregroundStyle(CiggyTheme.secondaryText)
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading) { _ in
						AxisGridLine().foregroundStyle(CiggyTheme.border)
						AxisValueLabel().foregroundStyle(CiggyTheme.secondaryText)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var detectionExperience: some View {
		if let review = reviewStore.latestReview {
			detectionReviewCard(review)
		} else {
			detectionReadyCard
		}
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
						Text("\(review.displayCount) \(review.displayCount == 1 ? "cigarette" : "cigarettes") detected")
							.font(.headline)
							.foregroundStyle(CiggyTheme.primaryText)
						Text(reviewSummaryText(review))
							.font(.subheadline)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer(minLength: 0)
				}

				if review.decision == .pending {
					Text("Already included in your total. Only respond if you want to teach Ciggy.")
						.font(.caption)
						.foregroundStyle(CiggyTheme.secondaryText)
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
								.background(CiggyTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.foregroundStyle(CiggyTheme.primaryText)
						.buttonStyle(.plain)
					}
					.font(.subheadline.weight(.bold))
				} else {
					Label(reviewDecisionText(review), systemImage: "checkmark.circle.fill")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(CiggyTheme.mint)
				}
			}
		}
	}

	private var detectionReadyCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label("Your little wrist sidekick", systemImage: "applewatch")
						.font(.subheadline.weight(.bold)).foregroundStyle(CiggyTheme.primaryText)
					Spacer(minLength: 0)
				}
				CiggyStatusPill(syncStatusTitle, systemImage: connectivity.isLiveSyncAvailable ? "applewatch.radiowaves.left.and.right" : "arrow.triangle.2.circlepath", color: connectivity.isLiveSyncAvailable ? CiggyTheme.mint : CiggyTheme.ember)
				Text("Your Watch gathers possible cigarettes into a quiet summary. You can adjust it whenever you like.")
					.font(.caption).foregroundStyle(CiggyTheme.secondaryText)
			}
		}
	}

	private func reviewSummaryText(_ review: DetectionReview) -> String {
		if review.origin == .watchHistory {
			return "Found in the last \(review.historyHours) \(review.historyHours == 1 ? "hour" : "hours") of Watch history."
		}
		return "Noticed by your Watch while motion monitoring was active."
	}

	private func reviewDecisionText(_ review: DetectionReview) -> String {
		switch review.decision {
		case .pending:
			return ""
		case .accurate:
			return "Marked accurate on your devices"
		case .adjusted:
			return "Count adjusted to \(review.displayCount) on your devices"
		}
	}

	private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
		VStack(alignment: .leading, spacing: 9) {
			Image(systemName: icon)
				.font(.subheadline.weight(.bold))
				.foregroundStyle(color)
			Text(value)
				.font(.title2.weight(.black))
				.foregroundStyle(CiggyTheme.primaryText)
			Text(title)
				.font(.caption2)
				.foregroundStyle(CiggyTheme.secondaryText)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(13)
		.background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(CiggyTheme.border, lineWidth: 1)
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
		}
	}
}

private struct DetectionCountAdjustmentView: View {
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
		NavigationStack {
			ZStack {
				CiggyBackdrop()
				VStack(spacing: 22) {
					Text("How many were actually smoked?")
						.font(.title2.weight(.black))
						.foregroundStyle(CiggyTheme.primaryText)
						.multilineTextAlignment(.center)

					Stepper(value: $count, in: 0...100) {
						HStack {
							Text("Correct count")
							Spacer()
							Text("\(count)")
								.font(.title.weight(.black))
								.foregroundStyle(CiggyTheme.mint)
						}
					}
					.padding()
					.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

					Text("This updates the total on iPhone and Apple Watch. Event times remain estimates from the detected window.")
						.font(.caption)
						.foregroundStyle(CiggyTheme.secondaryText)
						.multilineTextAlignment(.center)

					Button("Save corrected count") {
						onSave(count)
						dismiss()
					}
					.font(.headline)
					.foregroundStyle(CiggyTheme.deepInk)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 15)
					.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					.buttonStyle(.plain)
				}
				.padding(22)
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
