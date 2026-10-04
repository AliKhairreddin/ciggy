import Foundation
import UserNotifications

/// Local notifications for daily roasts, detections, and encouragement reminders.
public enum NotificationManager {
	private static let presentationDelegate = NotificationPresentationDelegate()
	private static let dailyRoastIdentifier = "daily-roast"

	public static func configurePresentation() {
		UNUserNotificationCenter.current().delegate = presentationDelegate
	}

	public static func requestAuthorization() async -> Bool {
		await withCheckedContinuation { cont in
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
				cont.resume(returning: granted)
			}
		}
	}

	public static func scheduleDailyRoast(_ roast: DailyRoast, preview: Bool = false, recap: Bool = false) {
		let content = UNMutableNotificationContent()
		content.title = preview ? "Preview: \(roast.title)" : roast.title
		content.body = roast.body
		content.sound = .default
		content.threadIdentifier = "daily-roasts"
		let request = UNNotificationRequest(
			identifier: preview ? "daily-roast-preview" : (recap ? "daily-roast-recap" : dailyRoastIdentifier),
			content: content,
			trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		)
		UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
	}

	public static func cancelPendingDailyRoasts() {
		UNUserNotificationCenter.current().removePendingNotificationRequests(
			withIdentifiers: [dailyRoastIdentifier, "daily-roast-preview", "daily-roast-recap"]
		)
	}

	public static func scheduleDetectionSummaryNotification(
		reviewID: UUID,
		count: Int,
		historyHours: Int
	) {
		guard count > 0 else { return }
		let content = UNMutableNotificationContent()
		content.title = "\(count) \(count == 1 ? "cigarette" : "cigarettes") detected"
		content.body = "Found in the last \(max(1, historyHours)) hours of Watch history. Already added—tap only if you want to review."
		content.sound = .default
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		let request = UNNotificationRequest(
			identifier: "detection-summary-\(reviewID.uuidString)",
			content: content,
			trigger: trigger
		)
		UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
	}

	public static func scheduleEncouragement(after seconds: TimeInterval, message: String) {
		let content = UNMutableNotificationContent()
		content.title = "Stay strong!"
		content.body = message
		content.sound = .default
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, seconds), repeats: false)
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
		UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
	}
}

private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.banner, .sound])
	}
}
