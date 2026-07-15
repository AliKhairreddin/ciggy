import Foundation
import UserNotifications

/// Local notifications for detections and encouragement reminders.
public enum NotificationManager {
	public static func requestAuthorization() async -> Bool {
		await withCheckedContinuation { cont in
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
				cont.resume(returning: granted)
			}
		}
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
