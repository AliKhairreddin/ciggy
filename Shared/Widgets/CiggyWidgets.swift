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
		let now = Date()
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
		case .today: "Today"
		case .remaining: "Daily Budget"
		case .elapsed: "Since Last Log"
		case .week: "Your Week"
		case .log: "Quick Log"
		}
	}
	var symbol: String {
		switch self {
		case .today: "leaf.fill"
		case .remaining: "target"
		case .elapsed: "timer"
		case .week: "chart.bar.fill"
		case .log: "plus.circle.fill"
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
		}.configurationDisplayName("Today").description("Today's count and daily-limit progress.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyBudgetWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyBudget", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .remaining)
		}.configurationDisplayName("Daily Budget").description("See how many logs remain within your daily limit.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyElapsedWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyElapsed", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .elapsed)
		}.configurationDisplayName("Since Last Log").description("A running timer from your most recent log.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyWeekWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyWeek", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .week)
		}.configurationDisplayName("Your Week").description("Seven days of logs at a glance.")
			.supportedFamilies(ciggyWidgetFamilies)
	}
}

public struct CiggyQuickLogWidget: Widget {
	public init() {}
	public var body: some WidgetConfiguration {
		StaticConfiguration(kind: "CiggyQuickLog", provider: CiggyWidgetProvider()) { entry in
			CiggyWidgetView(entry: entry, metric: .log)
		}.configurationDisplayName("Quick Log").description("Open Ciggy's logging screen with one tap.")
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
	private var subtitle: String {
		switch metric {
		case .today: "of \(entry.today.dailyLimit) daily limit"
		case .remaining: entry.today.dailyCount > entry.today.dailyLimit ? "\(entry.today.dailyCount - entry.today.dailyLimit) over today's limit" : "remaining within today's limit"
		case .elapsed: "since your last log"
		case .week: "logs in the last 7 days"
		case .log: "Log a cigarette"
		}
	}

	var body: some View {
		content
			.widgetURL(metric.url)
			.containerBackground(for: .widget) { palette.surface }
	}

	@ViewBuilder private var content: some View {
		if entry.snapshot == nil && metric != .log {
			Label("Open Ciggy", systemImage: "leaf")
		} else {
			switch family {
			case .accessoryInline:
				HStack(spacing: 4) { Image(systemName: metric.symbol); inlineValue }
			case .accessoryCircular:
				circular
			case .accessoryRectangular:
				VStack(alignment: .leading, spacing: 3) {
					Label(metric.title, systemImage: metric.symbol).font(.caption.weight(.semibold))
					value.font(.title3.weight(.bold)).minimumScaleFactor(0.6)
					if metric == .today || metric == .remaining {
						ProgressView(value: entry.today.progress).privacySensitive()
					} else { Text(subtitle).font(.caption2).lineLimit(1) }
				}
			#if os(watchOS)
			case .accessoryCorner:
				value.font(.title3.weight(.bold))
					.widgetLabel { Text(metric.title) }
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
				Gauge(value: entry.today.progress) { Image(systemName: metric.symbol) } currentValueLabel: {
					value.font(.headline)
				}.gaugeStyle(.accessoryCircular).privacySensitive()
			} else {
				VStack(spacing: 2) {
					Image(systemName: metric.symbol).font(.caption)
					value.font(.caption.weight(.bold)).minimumScaleFactor(0.45)
				}.padding(5)
			}
		}
	}

	#if os(iOS)
	private var isLarge: Bool {
		if #available(iOS 27.0, *), family == .systemExtraLargePortrait { return true }
		return family == .systemLarge || family == .systemExtraLarge
	}

	private var homeScreen: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Label("ciggy", systemImage: metric.symbol).font(.caption.weight(.black)).widgetAccentable()
				Spacer()
				if family != .systemSmall {
					Text(metric.title).font(.caption.weight(.semibold))
				}
			}.foregroundStyle(CiggyTheme.ember)
			if family == .systemMedium {
				HStack(spacing: 20) {
					primaryMetric
					Spacer(minLength: 0)
					if metric == .week { weekChart.frame(maxWidth: 145) }
					else if metric != .log { progressRing.frame(width: 60, height: 60) }
				}
			} else {
				primaryMetric
			}
			if isLarge {
				Divider()
				HStack {
					Text("YOUR WEEK").font(.caption2.weight(.bold)).tracking(1)
					Spacer()
					Text("\(weekCount) logs").font(.caption.weight(.semibold)).privacySensitive()
				}
				weekChart
				HStack {
					Link(destination: URL(string: "ciggy://log")!) { Label("Log", systemImage: "plus.circle.fill") }
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
			Text(subtitle).font(.caption).foregroundStyle(palette.secondaryText).fixedSize(horizontal: false, vertical: true)
			if metric == .today || metric == .remaining {
				ProgressView(value: entry.today.progress).tint(CiggyTheme.ember).privacySensitive()
			}
		}
	}

	private var progressRing: some View {
		ZStack {
			Circle().stroke(palette.border, lineWidth: 6)
			Circle().trim(from: 0, to: entry.today.progress).stroke(CiggyTheme.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
				.rotationEffect(.degrees(-90))
			Text("\(entry.today.dailyCount)/\(entry.today.dailyLimit)").font(.caption2.weight(.bold)).minimumScaleFactor(0.6)
		}.privacySensitive()
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
		case .today: Text("\(entry.today.dailyCount)").privacySensitive()
		case .remaining: Text("\(entry.today.remaining)").privacySensitive()
		case .week: Text("\(weekCount)").privacySensitive()
		case .log: Image(systemName: "plus.circle.fill").widgetAccentable()
		case .elapsed:
			if let last = entry.today.lastLoggedAt {
				Text(last, style: .timer).monospacedDigit().privacySensitive()
			} else { Text("No logs yet").font(.caption) }
		}
	}

	@ViewBuilder private var inlineValue: some View {
		switch metric {
		case .today: Text("\(entry.today.dailyCount)/\(entry.today.dailyLimit) today").privacySensitive()
		case .remaining: Text("\(entry.today.remaining) remaining").privacySensitive()
		case .week: Text("\(weekCount) this week").privacySensitive()
		case .log: Text("Log a cigarette")
		case .elapsed: value
		}
	}
}
#endif
