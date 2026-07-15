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

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					profileHeader
					todayHero
					detectionExperience
					quickMetrics
					weeklyChart
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				.padding(.bottom, 28)
			}
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository, settings: settings) }
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
		HStack {
			NavigationLink(destination: SettingsView()) {
				CiggyProfileMark(size: 46)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open profile and settings")
			Spacer()
			CiggyStatusPill(
				syncStatusTitle,
				systemImage: connectivity.isLiveSyncAvailable ? "applewatch.radiowaves.left.and.right" : "arrow.triangle.2.circlepath",
				color: connectivity.isLiveSyncAvailable ? CiggyTheme.mint : CiggyTheme.sunlight
			)
		}
	}

	private var todayHero: some View {
		CiggyPanel {
			HStack(spacing: 22) {
				ZStack {
					Circle()
						.stroke(CiggyTheme.elevatedSurface, lineWidth: 13)
					Circle()
						.trim(from: 0, to: max(0.025, viewModel.todayProgress))
						.stroke(
							viewModel.todayProgress >= 1 ? CiggyTheme.emberGradient : CiggyTheme.brandGradient,
							style: StrokeStyle(lineWidth: 13, lineCap: .round)
						)
						.rotationEffect(.degrees(-90))
					VStack(spacing: 0) {
						Text("\(viewModel.dailyCount)")
							.font(.system(size: 38, weight: .black, design: .rounded))
						Text("of \(settings.settings.dailyLimit)")
							.font(.caption.weight(.semibold))
							.foregroundStyle(CiggyTheme.secondaryText)
					}
				}
				.frame(width: 132, height: 132)

				VStack(alignment: .leading, spacing: 8) {
					Text("TODAY")
						.font(.caption2.weight(.bold))
						.tracking(1.6)
						.foregroundStyle(CiggyTheme.mint)
					Text(todayMessage)
						.font(.title3.weight(.bold))
						.foregroundStyle(.white)
					Text("Last logged \(viewModel.lastEventDescription.lowercased()).")
						.font(.subheadline)
						.foregroundStyle(CiggyTheme.secondaryText)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
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
				title: "Saved",
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
						Text("Last 7 days")
							.font(.headline)
							.foregroundStyle(.white)
						Text("Your smoking rhythm at a glance")
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
					.foregroundStyle(CiggyTheme.brandGradient)
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
							.foregroundStyle(.white)
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
						.foregroundStyle(.white)
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
		HStack(spacing: 14) {
			Image(systemName: "clock.arrow.circlepath")
				.font(.title2)
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(width: 48, height: 48)
				.background(CiggyTheme.brandGradient, in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				Text("Watch history is ready")
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.white)
				Text("Detected cigarettes appear here automatically as one quiet summary—no confirmation pop-up each time.")
					.font(.caption)
					.foregroundStyle(CiggyTheme.secondaryText)
			}
		}
		.padding(16)
		.background(CiggyTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.stroke(CiggyTheme.mint.opacity(0.18), lineWidth: 1)
		)
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
				.foregroundStyle(.white)
			Text(title)
				.font(.caption2)
				.foregroundStyle(CiggyTheme.secondaryText)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(13)
		.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.stroke(CiggyTheme.border, lineWidth: 1)
		)
	}

	private var todayMessage: String {
		let remaining = max(0, settings.settings.dailyLimit - viewModel.dailyCount)
		if viewModel.dailyCount == 0 { return "A clear start." }
		if remaining == 0 { return "Pause and reset." }
		return "\(remaining) left in your limit."
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
				CiggyTheme.appBackground.ignoresSafeArea()
				VStack(spacing: 22) {
					Text("How many were actually smoked?")
						.font(.title2.weight(.black))
						.foregroundStyle(.white)
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
