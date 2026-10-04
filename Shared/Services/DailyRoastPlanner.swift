import Foundation

public struct DailyRoast: Equatable, Sendable {
	public let title: String
	public let body: String
}

/// Copy is selected from the latest milestone, but always names the actual daily count.
public enum DailyRoastCopy {
	public static func variants(for count: Int) -> [DailyRoast] {
		let copy: [(String, String)]
		switch count {
		case ..<5:
			copy = [
				("And we're off.", "{count} {cigarettes} today. Your lungs did not RSVP to this."),
				("A puff. Bold choice.", "{count} {cigarettes} today. Fresh air was right there."),
				("A smoky opening act.", "{count} {cigarettes} today. Your lungs have entered the chat. They're not happy."),
				("Well, that escalated.", "{count} {cigarettes} today. A tiny bonfire, sponsored by your lungs.")
			]
		case 5..<10:
			copy = [
				("Five-star smoke machine.", "{count} cigarettes today. Your lungs would give this experience zero stars."),
				("Collecting bad decisions?", "{count} cigarettes today. Unfortunately, there's no loyalty reward for this."),
				("A round of applause. Sort of.", "{count} cigarettes today. Your lungs are clapping. Very sarcastically."),
				("Your lungs called.", "{count} cigarettes today. They'd like to speak to the manager.")
			]
		case 10..<15:
			copy = [
				("Congrats, I guess.", "{count} cigarettes today. Your lungs must be absolutely thrilled."),
				("Double digits. Single bad idea.", "{count} cigarettes today. Your lungs would like to unsubscribe."),
				("Achievement unlocked: ashtray.", "{count} cigarettes today. Turning your lungs into a smoke lounge. Very classy."),
				("A breathtaking performance.", "{count} cigarettes today. And yes, the sarcasm is doing the heavy lifting.")
			]
		case 15..<20:
			copy = [
				("Overachieving. Unfortunately.", "{count} cigarettes today. If bad decisions were a sport, you'd be on the podium."),
				("Your lungs want a union.", "{count} cigarettes today. They're demanding better working conditions."),
				("Smoke alarm energy.", "{count} cigarettes today. Your lungs are drafting a strongly worded email."),
				("Really committing to the bit.", "{count} cigarettes today. Maybe give the lungs a commercial break?")
			]
		case 20..<25:
			copy = [
				("Standing ovation withheld.", "{count} cigarettes today. Your lungs have filed a formal complaint."),
				("Employee of the month: your lighter.", "{count} cigarettes today. Your lungs, meanwhile, are asking for sick leave."),
				("Congrats on the smoke marathon.", "{count} cigarettes today. The finish line could have been several cigarettes ago."),
				("A whole lot of nope.", "{count} cigarettes today. Your lungs would like a refund on today.")
			]
		default:
			copy = [
				("The lighter needs a vacation.", "{count} cigarettes today. Your lungs would also like some paid time off."),
				("An impressive lack of fresh air.", "{count} cigarettes today. Your lungs are updating their résumé."),
				("Plot twist: you can stop here.", "{count} cigarettes today. Nobody asked for a smoke-filled sequel."),
				("Your lungs left you on read.", "{count} cigarettes today. Even the ashtray thinks that's a bit much.")
			]
		}
		return (copy + DailyRoastLibrary.additionalCountVariants(for: count)).map {
			DailyRoast(title: $0.0, body: $0.1
				.replacingOccurrences(of: "{count}", with: "\(count)")
				.replacingOccurrences(of: "{cigarettes}", with: count == 1 ? "cigarette" : "cigarettes"))
		}
	}

	static func milestone(for count: Int) -> Int {
		count < 5 ? min(1, max(0, count)) : count / 5 * 5
	}
}

/// Persists a daily high-water mark so replay, relaunch, and count corrections
/// cannot repeatedly roast the same milestone. Disabled notifications consume it too.
@MainActor
public final class DailyRoastPlanner {
	private struct State: Codable {
		var day: Date
		var highestCount: Int
		var lastVariants: [DailyRoastScenario: Int]
		var lastRecapDay: Date?
	}

	private let defaults: UserDefaults
	private let storageKey: String
	private var state: State?

	public init(userDefaults: UserDefaults = .standard, storageKey: String = "Ciggy.dailyRoasts.v1") {
		defaults = userDefaults
		self.storageKey = storageKey
		if let data = defaults.data(forKey: storageKey) {
			state = try? JSONDecoder().decode(State.self, from: data)
		}
	}

	public func next(
		count: Int,
		dailyLimit: Int = 10,
		enabled: Bool,
		at date: Date = Date(),
		calendar: Calendar = .current
	) -> DailyRoast? {
		prepareDay(date, calendar: calendar)
		let count = max(0, count)
		guard var current = state, count > current.highestCount else { return nil }
		let previousCount = current.highestCount
		current.highestCount = count
		state = current
		let limit = UserSettings.clampedDailyLimit(dailyLimit)
		// A batch that skips several milestones produces only its highest crossed threshold.
		let candidates: [(Int, DailyRoastScenario)] = [
			(DailyRoastCopy.milestone(for: count), .countScenario(for: count)),
			(limit, .limitReached),
			(limit + 1, .limitExceeded)
		]
		var selected: (Int, DailyRoastScenario)?
		for candidate in candidates where candidate.0 > previousCount && candidate.0 <= count {
			if candidate.0 > (selected?.0 ?? 0) { selected = candidate }
		}
		let roast = enabled ? selected.map { select($0.1, count: count, limit: limit) } : nil
		save()
		return roast
	}

	/// One positive recap for a completed tracked day when the iPhone next opens or syncs.
	public func recap(
		events: [SmokingEvent],
		dailyLimit: Int,
		enabled: Bool,
		at date: Date = Date(),
		calendar: Calendar = .current
	) -> DailyRoast? {
		prepareDay(date, calendar: calendar)
		let today = calendar.startOfDay(for: date)
		guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
		      let dayBefore = calendar.date(byAdding: .day, value: -1, to: yesterday),
		      events.contains(where: { $0.timestamp < yesterday }),
		      state?.lastRecapDay.map({ calendar.isDate($0, inSameDayAs: yesterday) }) != true
		else { return nil }
		let count = events.filter { $0.timestamp >= yesterday && $0.timestamp < today }.count
		let previous = events.filter { $0.timestamp >= dayBefore && $0.timestamp < yesterday }.count
		let limit = UserSettings.clampedDailyLimit(dailyLimit)
		let scenario: DailyRoastScenario?
		if count == 0 { scenario = .smokeFree }
		else if count < previous { scenario = .reduced }
		else if count < limit { scenario = .belowLimit }
		else { scenario = nil }
		state?.lastRecapDay = yesterday
		let roast = enabled ? scenario.map { select($0, count: count, limit: limit, previousCount: previous) } : nil
		save()
		return roast
	}

	private func prepareDay(_ date: Date, calendar: Calendar) {
		if state == nil {
			state = State(day: calendar.startOfDay(for: date), highestCount: 0, lastVariants: [:])
		}
		if let current = state, calendar.isDate(current.day, inSameDayAs: date) == false {
			state?.day = calendar.startOfDay(for: date)
			state?.highestCount = 0
		}
	}

	private func select(_ scenario: DailyRoastScenario, count: Int, limit: Int, previousCount: Int = 0) -> DailyRoast {
		let variants = DailyRoastCopy.variants(for: scenario, count: count, limit: limit, previousCount: previousCount)
		// Random starting point, then a complete cycle before a scenario repeats any line.
		let index = state?.lastVariants[scenario].map { ($0 + 1) % variants.count }
			?? Int.random(in: variants.indices)
		state?.lastVariants[scenario] = index
		return variants[index]
	}

	private func save() {
		if let state, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
	}
}
