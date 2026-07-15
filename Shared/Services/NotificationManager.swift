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

	public static func scheduleDetectionCandidateNotification(candidateID: UUID) {
		let content = UNMutableNotificationContent()
		content.title = "Smoked 1?"
		content.body = "Ciggy noticed a repeated hand-to-mouth pattern. Tap to confirm."
		content.sound = .default
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		let request = UNNotificationRequest(identifier: candidateID.uuidString, content: content, trigger: trigger)
		UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
	}

	public static func removeDetectionCandidateNotification(candidateID: UUID) {
		UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [candidateID.uuidString])
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [candidateID.uuidString])
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
