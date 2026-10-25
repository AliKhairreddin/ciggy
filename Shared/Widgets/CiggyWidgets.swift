#if (os(iOS) || os(watchOS)) && canImport(WidgetKit)
import Foundation
import SwiftUI
import WidgetKit

private struct CiggyWidgetEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot?
	var today: LiveActivitySnapshot { (snapshot ?? WidgetSnapshot(events: [], dailyLimit: 10)).today(at: date) }
	var week: [WidgetSnapshot.Day] { snapshot?.week(at: date) ?? [] }
}

private struct CiggyWidgetProvider: TimelineProvider {
	var usesLivePreviewTime = false
	func placeholder(in context: Context) -> CiggyWidgetEntry { previewEntry() }
	func getSnapshot(in context: Context, completion: @escaping (CiggyWidgetEntry) -> Void) {
		completion(context.isPreview ? previewEntry() : CiggyWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore().read()))
	}
	func getTimeline(in context: Context, completion: @escaping (Timeline<CiggyWidgetEntry>) -> Void) {
		let now = Date()
		let snapshot = WidgetSnapshotStore().read()
		let calendar = Calendar.current
		// Precomputed midnight entries reset daily totals even if the app isn't opened.
		let dates = [now] + (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now)) }
		completion(Timeline(entries: dates.map { CiggyWidgetEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
	}
	private func previewEntry() -> CiggyWidgetEntry {
		// A daytime example always demonstrates 3 recorded / 7 left, even when
		// someone opens the gallery shortly after midnight. Never persisted.
		let current = Date()
		let now = usesLivePreviewTime ? current : Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: current) ?? current
		let events = [30, 120, 240, 1_500, 2_940, 4_380].map {
			SmokingEvent(timestamp: now.addingTimeInterval(Double(-$0 * 60)), source: .manual)
		}
		return CiggyWidgetEntry(date: now, snapshot: WidgetSnapshot(events: events, dailyLimit: 10, now: now))
	}
}

private enum WidgetMetric {
	case today, remaining, elapsed, week, log
	var title: String {
		switch self {
		case .today: "Cigarettes Today"
		case .remaining: "Daily Limit Remaining"
		case .elapsed: "Since Last Log"
		case .week: "Last 7 Days"
		case .log: "Log a Cigarette"
		}
	}
	var icon: CiggyIcon {
		switch self {
		case .today: .cigarette
		case .remaining: .limit
		case .elapsed: .elapsed
		case .week: .reports
		case .log: .log
		}
	}
	var url: URL {
		URL(string: "ciggy://\(self == .week ? "reports" : self == .remaining ? "goals" : self == .log ? "log" : "today")")!
	}
}

private var ciggyWidgetFamilies: [WidgetFamily] {
	#if os(watchOS)
	[.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
	#else
	var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
	if #available(iOS 27.0, *) { families.append(.systemExtraLargePortrait) }
	return families
	#endif
}

public struct CiggyTodayWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyToday", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .today)
		}.configurationDisplayName("Cigarettes Today").description("Today's paper trail: cigarettes recorded, including automatic estimates. Tap to open Today.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyBudgetWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyBudget", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .remaining)
		}.configurationDisplayName("Daily Limit Remaining").description("Your line in the ash: cigarettes left before your daily limit, or how far over it you are. Tap to adjust the limit.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyElapsedWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyElapsed", provider: CiggyWidgetProvider(usesLivePreviewTime: true)) { entry in
			CiggyWidgetView(entry: entry, metric: .elapsed)
		}.configurationDisplayName("Since Last Log").description("Time since your latest recorded cigarette. A timer, not a smoke-free certificate.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyWeekWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyWeek", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .week)
		}.configurationDisplayName("Last 7 Days").description("A week of receipts: cigarettes recorded today and over the previous six days. Tap to open Reports.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyQuickLogWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyQuickLog", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .log)
		}.configurationDisplayName("Log a Cigarette").description("One slipped past the paperwork? Open Ciggy's logging form, then save it in the app.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

private struct CiggyWidgetView: View {
	@Environment(\.widgetFamily) private var family
	@Environment(\.colorScheme) private var colorScheme
	let entry: CiggyWidgetEntry
	let metric: WidgetMetric
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	private var weekCount: Int { entry.week.reduce(0) { $0 + $1.count } }
	private var logIconSize: CGFloat {
		#if os(watchOS)
		if family == .accessoryCorner { return 18 }
		#endif
		return 30
	}
	private var overLimit: Int { max(0, entry.today.dailyCount - entry.today.dailyLimit) }
	private var usesCompactHomeCopy: Bool {
		#if os(iOS)
		family == .systemSmall
		#else
		false
		#endif
	}
	private var metricProgress: Double {
		metric == .remaining ? Double(entry.today.remaining) / Double(entry.today.dailyLimit) : entry.today.progress
	}
	private var compactLabel: String {
		switch metric {
		case .today: "today"
		case .remaining: overLimit > 0 ? "over" : entry.today.remaining == 0 ? "at limit" : "left"
		case .elapsed: "since log"
		case .week: "7 days"
		case .log: "log"
		}
	}
	private var cornerLabel: String {
		switch metric {
		case .today: "Cigarettes today"
		case .remaining: overLimit > 0 ? "Over daily limit" : entry.today.remaining == 0 ? "Daily limit reached" : "Left to daily limit"
		default: metric.title
		}
	}
	private var limitSummary: String {
		if overLimit > 0 { return "\(overLimit) cigarettes over your daily limit of \(entry.today.dailyLimit)" }
		if entry.today.remaining == 0 { return "Daily limit of \(entry.today.dailyLimit) reached" }
		return "\(entry.today.remaining) cigarettes left before your daily limit of \(entry.today.dailyLimit)"
	}
	private var subtitle: String {
		switch metric {
		case .today: return usesCompactHomeCopy ? "recorded · limit \(entry.today.dailyLimit)" : "cigarettes recorded · limit \(entry.today.dailyLimit)"
		case .remaining:
			if overLimit > 0 { return "\(usesCompactHomeCopy ? "over" : "cigarettes over") · limit \(entry.today.dailyLimit)" }
			if entry.today.remaining == 0 { return "daily limit of \(entry.today.dailyLimit) reached" }
			return "\(usesCompactHomeCopy ? "left" : "cigarettes left") · limit \(entry.today.dailyLimit)"
		case .elapsed: return "since last recorded cigarette"
		case .week: return "cigarettes recorded in 7 days"
		case .log: return "Add one to the paper trail"
		}
	}

	var body: some View {
		content
			.widgetURL(metric.url)
			.containerBackground(for: .widget) { palette.surface }
	}

	@ViewBuilder private var content: some View {
		if entry.snapshot == nil && metric != .log {
			Label { Text("Open Ciggy") } icon: { CiggyIconView(.cigarette, size: 14) }
		} else {
			switch family {
			case .accessoryInline:
				HStack(spacing: 4) { CiggyIconView(metric.icon, size: 12); inlineValue }
			case .accessoryCircular:
				circular
			case .accessoryRectangular:
				VStack(alignment: .leading, spacing: 2) {
					Label { Text(metric == .remaining ? "Daily limit" : metric.title) } icon: { CiggyIconView(metric.icon, size: 12) }
						.font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
					HStack(alignment: .firstTextBaseline, spacing: 4) {
						value.font(.title3.weight(.bold)).minimumScaleFactor(0.6)
						if metric == .today || metric == .remaining { Text(compactLabel).font(.caption2) }
					}.lineLimit(1)
					if metric == .today || metric == .remaining {
						ProgressView(value: metricProgress).privacySensitive().accessibilityHidden(true)
					} else { Text(subtitle).font(.caption2).lineLimit(1) }
				}
			#if os(watchOS)
			case .accessoryCorner:
				value.font(.title3.weight(.bold))
					.widgetLabel { Text(cornerLabel) }
			#endif
			default:
				#if os(iOS)
				homeScreen
				#else
				circular
				#endif
			}
		}
	}

	private var circular: some View {
		ZStack {
			AccessoryWidgetBackground()
			if metric == .today || metric == .remaining {
				Gauge(value: metricProgress) { CiggyIconView(metric.icon, size: 10) } currentValueLabel: {
					VStack(spacing: 0) {
						value.font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
						Text(compactLabel).font(.system(size: 8, weight: .semibold)).lineLimit(1)
					}
				}.gaugeStyle(.accessoryCircular).privacySensitive()
			} else if metric == .log {
				VStack(spacing: 2) {
					CiggyIconView(.log, size: 24)
					Text("Log").font(.system(size: 8, weight: .semibold))
				}.padding(5)
					.accessibilityElement(children: .ignore)
					.accessibilityLabel("Open Ciggy to log a cigarette")
			} else {
				VStack(spacing: 1) {
					CiggyIconView(metric.icon, size: 12)
					value.font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.45)
					Text(compactLabel).font(.system(size: 8, weight: .semibold))
				}.padding(3)
			}
		}
	}

	#if os(iOS)
	private var isLarge: Bool {
		if #available(iOS 27.0, *), family == .systemExtraLargePortrait { return true }
		return family == .systemLarge || family == .systemExtraLarge
	}

	private var homeScreen: some View {
		VStack(alignment: .leading, spacing: usesCompactHomeCopy ? 8 : 10) {
			HStack(alignment: .top, spacing: 7) {
				CiggyIconView(metric.icon, size: 17).widgetAccentable()
				VStack(alignment: .leading, spacing: 2) {
					Text("ciggy").font(.caption2.weight(.black)).widgetAccentable()
					Text(metric.title).font(.caption.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
				}
				Spacer()
			}.foregroundStyle(CiggyTheme.ember)
			if family == .systemMedium {
				HStack(spacing: 20) {
					primaryMetric
					Spacer(minLength: 0)
					if metric == .week { weekChart.frame(maxWidth: 145) }
					else if metric == .today || metric == .remaining { progressRing.frame(width: 60, height: 60) }
				}
			} else {
				primaryMetric
			}
			if isLarge {
				Divider()
				HStack {
					Text("LAST 7 DAYS").font(.caption2.weight(.bold)).tracking(1)
					Spacer()
					Text("\(weekCount) logs").font(.caption.weight(.semibold)).privacySensitive()
				}
				weekChart
				HStack {
					Link(destination: URL(string: "ciggy://log")!) {
						Label { Text("Log") } icon: { CiggyIconView(.log, size: 13) }
					}
					Spacer()
					Link("Reports", destination: URL(string: "ciggy://reports")!)
				}.font(.caption.weight(.bold)).foregroundStyle(CiggyTheme.ember)
			}
			Spacer(minLength: 0)
		}.foregroundStyle(palette.primaryText)
	}
	#endif

	private var primaryMetric: some View {
		VStack(alignment: .leading, spacing: 5) {
			value.font(.system(size: metric == .elapsed ? 29 : 38, weight: .black, design: .rounded))
				.minimumScaleFactor(0.5).lineLimit(1)
				.frame(height: 44, alignment: .leading)
			Text(subtitle).font(.caption).foregroundStyle(palette.secondaryText).fixedSize(horizontal: false, vertical: true)
			if metric == .today || metric == .remaining {
				ProgressView(value: metricProgress).tint(CiggyTheme.ember).privacySensitive().accessibilityHidden(true)
			}
		}
	}

	private var progressRing: some View {
		ZStack {
			Circle().stroke(palette.border, lineWidth: 6)
			Circle().trim(from: 0, to: metricProgress).stroke(CiggyTheme.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
				.rotationEffect(.degrees(-90))
			VStack(spacing: 1) {
				Text(metric == .remaining ? "\(entry.today.remaining)/\(entry.today.dailyLimit)" : "\(entry.today.dailyCount)/\(entry.today.dailyLimit)")
					.font(.caption2.weight(.bold)).minimumScaleFactor(0.6)
				Text(metric == .remaining ? "left" : "recorded").font(.system(size: 8))
			}
		}.privacySensitive().accessibilityHidden(true)
	}

	private var weekChart: some View {
		HStack(alignment: .bottom, spacing: 6) {
			ForEach(entry.week) { day in
				VStack(spacing: 4) {
					Text("\(day.count)").font(.caption2).minimumScaleFactor(0.5)
					RoundedRectangle(cornerRadius: 4)
						.fill(Calendar.current.isDate(day.date, inSameDayAs: entry.date) ? CiggyTheme.ember : CiggyTheme.peach)
						.frame(height: max(3, 52 * Double(day.count) / Double(max(1, entry.week.map(\.count).max() ?? 1))))
					Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption2)
				}.frame(maxWidth: .infinity)
			}
		}.frame(height: 90, alignment: .bottom).privacySensitive()
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(entry.week.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \($0.count) logs" }.joined(separator: ", "))
	}

	@ViewBuilder private var value: some View {
		switch metric {
		case .today:
			Text("\(entry.today.dailyCount)").privacySensitive()
				.accessibilityLabel("\(entry.today.dailyCount) cigarettes recorded today")
		case .remaining:
			Text(overLimit > 0 ? "+\(overLimit)" : "\(entry.today.remaining)").privacySensitive()
				.accessibilityLabel(limitSummary)
		case .week:
			Text("\(weekCount)").privacySensitive()
				.accessibilityLabel("\(weekCount) cigarettes recorded in the last seven days")
		case .log:
			ZStack { CiggyIconView(.log, size: logIconSize).widgetAccentable() }
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("Open Ciggy to log a cigarette")
		case .elapsed:
			if let last = entry.today.lastLoggedAt {
				Text(last, style: .timer).monospacedDigit().privacySensitive()
					.accessibilityLabel("Time since last recorded cigarette")
					.accessibilityValue(Text(last, style: .timer))
			} else { Text("No logs yet").font(.caption) }
		}
	}

	@ViewBuilder private var inlineValue: some View {
		switch metric {
		case .today:
			Text("\(entry.today.dailyCount) today").privacySensitive()
				.accessibilityLabel("\(entry.today.dailyCount) cigarettes recorded today")
		case .remaining:
			Text(overLimit > 0 ? "+\(overLimit) over limit" : entry.today.remaining == 0 ? "0 · limit reached" : "\(entry.today.remaining) left to limit")
				.privacySensitive().accessibilityLabel(limitSummary)
		case .week:
			Text("\(weekCount) in 7 days").privacySensitive()
				.accessibilityLabel("\(weekCount) cigarettes recorded in the last seven days")
		case .log: Text("Log a cigarette")
		case .elapsed: value
		}
	}
}
#endif
