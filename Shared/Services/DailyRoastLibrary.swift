import Foundation

public enum DailyRoastScenario: String, Codable, CaseIterable, Sendable {
	case first, five, ten, fifteen, twenty, heavy
	case limitReached, limitExceeded, belowLimit, reduced, smokeFree

	static func countScenario(for count: Int) -> Self {
		switch count {
		case ..<5: return .first
		case 5..<10: return .five
		case 10..<15: return .ten
		case 15..<20: return .fifteen
		case 20..<25: return .twenty
		default: return .heavy
		}
	}
}

public extension DailyRoastCopy {
	static func variants(for scenario: DailyRoastScenario, count: Int, limit: Int = 10, previousCount: Int = 0) -> [DailyRoast] {
		switch scenario {
		case .first, .five, .ten, .fifteen, .twenty, .heavy: return variants(for: count)
		default: break
		}
		return DailyRoastLibrary.achievementVariants(for: scenario).map {
			DailyRoast(title: $0.0, body: $0.1
				.replacingOccurrences(of: "{count}", with: "\(count)")
				.replacingOccurrences(of: "{limit}", with: "\(limit)")
				.replacingOccurrences(of: "{previous}", with: "\(previousCount)")
				.replacingOccurrences(of: "{cigarettes}", with: count == 1 ? "cigarette" : "cigarettes"))
		}
	}

	/// All 110 messages with sample values, for a preview that never alters logged events.
	static var previews: [DailyRoast] {
		DailyRoastScenario.allCases.flatMap { scenario in
			let count: Int
			switch scenario {
			case .first: count = 1
			case .five: count = 5
			case .ten: count = 10
			case .fifteen: count = 15
			case .twenty: count = 20
			case .heavy: count = 30
			case .limitReached: count = 10
			case .limitExceeded: count = 11
			case .belowLimit, .reduced: count = 4
			case .smokeFree: count = 0
			}
			return variants(for: scenario, count: count, previousCount: 8)
		}
	}
}

enum DailyRoastLibrary {
	static func additionalCountVariants(for count: Int) -> [(String, String)] {
		switch count {
		case ..<5:
			return [
				("The lighter clocks in.", "{count} {cigarettes} today. The lungs were hoping for a day off."),
				("Starting strong. Wrong sport.", "{count} {cigarettes} today. This is a habit tracker, not a high-score board."),
				("An unsolicited smoke delivery.", "{count} {cigarettes} today. Your lungs ordered oxygen. Check the receipt."),
				("Today's plot twist.", "{count} {cigarettes} today. Apparently the villain brought a lighter."),
				("Opening credits: smoke.", "{count} {cigarettes} today. We can still give this day a better ending."),
				("Air, but make it questionable.", "{count} {cigarettes} today. Your lungs are giving you the side-eye.")
			]
		case 5..<10:
			return [
				("A very smoky group project.", "{count} cigarettes today. The lungs are doing all the work and getting none of the credit."),
				("The ashtray is getting ideas.", "{count} cigarettes today. It thinks this is a long-term relationship."),
				("Fresh air has left the building.", "{count} cigarettes today. Your lungs preferred the original atmosphere."),
				("A questionable collection.", "{count} cigarettes today. Have you considered collecting literally anything else?"),
				("Your lighter feels appreciated.", "{count} cigarettes today. Your lungs cannot relate."),
				("The smoke has a sequel.", "{count} cigarettes today. The reviews from your lungs are brutal.")
			]
		case 10..<15:
			return [
				("Ten out of ten? Hardly.", "{count} cigarettes today. That's a count, not a customer satisfaction score."),
				("Your lungs muted the group chat.", "{count} cigarettes today. They've heard enough from the lighter."),
				("A milestone with terrible PR.", "{count} cigarettes today. No ribbon-cutting ceremony for this one."),
				("The lungs are not impressed.", "{count} cigarettes today. Somehow, 'more smoke' wasn't on their vision board."),
				("Congrats on the double digits.", "{count} cigarettes today. Your lungs are celebrating by filing a complaint."),
				("Your lighter has main-character energy.", "{count} cigarettes today. Maybe let fresh air have a scene?")
			]
		case 15..<20:
			return [
				("An ambitious smoke schedule.", "{count} cigarettes today. Your lungs did not approve this calendar invite."),
				("The lungs have notes.", "{count} cigarettes today. All of their notes say 'please stop.'"),
				("Your ashtray got promoted.", "{count} cigarettes today. Your lungs are considering resignation."),
				("A smoky résumé.", "{count} cigarettes today. 'Proficient in bad ideas' is quite the skill."),
				("Nobody ordered the smoke buffet.", "{count} cigarettes today. Your lungs would like to leave the restaurant."),
				("A questionable personal best.", "{count} cigarettes today. Let's find something else to be competitive about.")
			]
		case 20..<25:
			return [
				("This party has terrible ventilation.", "{count} cigarettes today. Your lungs are looking for the exit."),
				("An ashtray's dream day.", "{count} cigarettes today. Everyone else has concerns."),
				("The lighter is working overtime.", "{count} cigarettes today. Unfortunately, your lungs don't get overtime pay."),
				("Smoke: renewed for another season.", "{count} cigarettes today. Your lungs are cancelling the subscription."),
				("A very expensive smoke signal.", "{count} cigarettes today. Message received. Please switch to texting."),
				("Your lungs opened a support ticket.", "{count} cigarettes today. Priority: very much not low.")
			]
		default:
			return [
				("Smoke machine mode: enough.", "{count} cigarettes today. You're a person, not concert equipment."),
				("The ashtray wants boundaries.", "{count} cigarettes today. Even it needs some personal space."),
				("A cloud with terrible intentions.", "{count} cigarettes today. Your lungs would prefer a clear forecast."),
				("Your lighter deserves a break.", "{count} cigarettes today. Put it down before it starts charging consulting fees."),
				("The lungs called an emergency meeting.", "{count} cigarettes today. The only agenda item is 'less of this.'"),
				("All smoke, no applause.", "{count} cigarettes today. Ending the streak of lighting up is allowed.")
			]
		}
	}

	static func achievementVariants(for scenario: DailyRoastScenario) -> [(String, String)] {
		switch scenario {
		case .limitReached:
			return [
				("The limit has entered the chat.", "{count} today. Your daily limit is {limit}. It's a ceiling, not a challenge."),
				("That's your stop sign.", "{count} today. You've reached your {limit}-cigarette limit. The lighter can clock out."),
				("Budget exhausted: smoke edition.", "{count} today. Your limit of {limit} has no bonus round."),
				("Daily allowance: fully toasted.", "{count} today. You set a limit of {limit}. Time to respect your own memo."),
				("You've reached the fence.", "{count} today, with a limit of {limit}. The other side doesn't need exploring."),
				("The scoreboard says stop.", "{count} today. Your {limit}-cigarette limit would appreciate staying a limit."),
				("Your goal is tapping the mic.", "{count} today. Limit: {limit}. Is this thing on?"),
				("No overtime for the lighter.", "{count} today. You've hit your limit of {limit}. Call it a day."),
				("That's the final boarding call.", "{count} today. Your limit of {limit} suggests the next trip should be for fresh air."),
				("Full capacity. Close the smoke lounge.", "{count} today. You've reached your daily limit of {limit}.")
			]
		case .limitExceeded:
			return [
				("The limit was not a suggestion.", "{count} today, past your limit of {limit}. Your goal would like a word."),
				("A bold interpretation of 'limit.'", "{count} today. You set {limit}. The math is raising an eyebrow."),
				("Over budget. Under fresh air.", "{count} today, beyond your {limit}-cigarette limit. Let's stop the extra spending."),
				("You crossed your own stop sign.", "{count} today. Limit: {limit}. There's still time to park the lighter."),
				("The bonus round nobody wanted.", "{count} today, over your limit of {limit}. Your lungs declined the expansion pack."),
				("Your daily goal is typing...", "{count} today. Limit: {limit}. Its message is probably not 'congrats.'"),
				("The boundary has been roasted.", "{count} today, past {limit}. A rough day doesn't need another cigarette."),
				("That limit deserves an apology.", "{count} today. Your goal was {limit}. Give it a better ending from here."),
				("Oops has a cigarette count.", "{count} today, beyond your limit of {limit}. No need to keep adding to the plot."),
				("Goal exceeded. Wrong direction.", "{count} today. The limit was {limit}. We were aiming for less, superstar.")
			]
		case .belowLimit:
			return [
				("Under the limit. Over the drama.", "{count} {cigarettes} logged yesterday, below your limit of {limit}. Your lighter survived being ignored."),
				("Look who respected a boundary.", "Yesterday: {count} logged. Limit: {limit}. Your lungs appreciate the restraint."),
				("The lighter got fewer shifts.", "{count} logged yesterday, under your {limit}-cigarette goal. Keep cutting its hours."),
				("A goal with a happy ending.", "{count} logged yesterday against a limit of {limit}. That's progress worth repeating."),
				("Your limit feels seen.", "{count} logged yesterday. You stayed below {limit}. Boundaries look good on you."),
				("An actual reason to say congrats.", "{count} logged yesterday, under your limit of {limit}. This applause is real."),
				("The smoke budget has leftovers.", "{count} logged yesterday out of a limit of {limit}. Please don't spend the leftovers."),
				("You kept your own promise.", "{count} logged yesterday, below {limit}. Nice to see the goal getting some respect."),
				("Your ashtray had a quieter day.", "{count} logged yesterday, under your limit of {limit}. It will cope."),
				("Less smoke. More follow-through.", "Yesterday's {count} logged stayed below {limit}. Keep that energy today.")
			]
		case .reduced:
			return [
				("A downward trend we approve of.", "{count} logged yesterday, down from {previous} the day before. Your lighter is losing influence."),
				("Less smoke, more plot development.", "Yesterday: {count} logged. The day before: {previous}. Character growth looks good on you."),
				("Your lighter got demoted.", "From {previous} to {count} logged yesterday. That's a smaller workload worth keeping."),
				("Finally, a smaller number.", "{count} logged yesterday after {previous} the day before. We're fans of this direction."),
				("The smoke sequel has less smoke.", "{count} logged yesterday, versus {previous} the day before. A rare sequel improvement."),
				("The ashtray noticed the slowdown.", "From {previous} to {count} logged yesterday. It has filed absolutely no complaint."),
				("Your lungs appreciate the edit.", "{count} logged yesterday, down from {previous}. Keep deleting scenes with the lighter."),
				("You're shrinking the bad habit.", "Yesterday's {count} logged beats the previous day's {previous}. Small wins still count."),
				("A less smoky version of you.", "{count} logged yesterday after {previous}. We like this update."),
				("Actual progress. Hold the sarcasm.", "{count} logged yesterday, fewer than {previous} the day before. You earned this one.")
			]
		case .smokeFree:
			return [
				("Zero. Now that's a flex.", "No cigarettes logged yesterday. Your lighter had an existential crisis."),
				("The ashtray was unemployed.", "Zero cigarettes logged yesterday. We fully support this career change."),
				("Fresh air got the starring role.", "No cigarettes logged yesterday. Your lungs loved the casting decision."),
				("Congrats. With zero sarcasm.", "Zero cigarettes logged yesterday. That's the kind of achievement we're here for."),
				("Your lighter felt neglected.", "No cigarettes logged yesterday. It will get over it. Keep going."),
				("A smoke-free entry in the diary.", "Zero cigarettes logged yesterday. A very good plot twist."),
				("The best count is no count.", "No cigarettes logged yesterday. Your lungs are sending a thank-you note."),
				("Yesterday came with extra air.", "Zero cigarettes logged. The lighter can stay in retirement."),
				("You ghosted the cigarette.", "No cigarettes logged yesterday. This is one ghosting we can get behind."),
				("Achievement unlocked: leave it unlit.", "Zero cigarettes logged yesterday. Take the win and bring it into today.")
			]
		default: return []
		}
	}
}
