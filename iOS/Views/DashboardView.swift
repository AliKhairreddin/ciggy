#if os(iOS)
import Charts
import CiggyShared
import SwiftUI

struct DashboardView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = DashboardViewModel()
	@ObservedObject private var connectivity = ConnectivityManager.shared

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					brandHeader
					todayHero
					quickMetrics
					weeklyChart
					detectionCard
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				.padding(.bottom, 28)
			}
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(repository: repository, settings: settings) }
	}

	private var brandHeader: some View {
		HStack(spacing: 12) {
			CiggyBrandMark(size: 46)
			VStack(alignment: .leading, spacing: 1) {
				Text("ciggy")
					.font(.system(size: 30, weight: .black, design: .rounded))
					.foregroundStyle(.white)
				Text("notice the pattern. change the pattern.")
					.font(.caption)
					.foregroundStyle(CiggyTheme.secondaryText)
			}
			Spacer()
			CiggyStatusPill(
				syncStatusTitle,
				systemImage: connectivity.isLiveSyncAvailable ? "applewatch.radiowaves.left.and.right" : "arrow.triangle.2.circlepath",
				color: connectivity.isLiveSyncAvailable ? CiggyTheme.mint : CiggyTheme.sunlight
			)
		}
		.accessibilityElement(children: .combine)
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

	private var detectionCard: some View {
		HStack(spacing: 14) {
			Image(systemName: "hand.raised.fingers.spread.fill")
				.font(.title2)
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(width: 48, height: 48)
				.background(CiggyTheme.brandGradient, in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				Text("Motion-first detection")
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.white)
				Text("Your Watch looks for a repeated hand-to-mouth pattern, then asks you to confirm.")
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
		}
	}
}
#endif
