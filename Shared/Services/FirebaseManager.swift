import Foundation

/// Placeholder Firebase manager to stub future cloud sync.
public enum FirebaseManager {
	public static func signInAnonymously() async throws {
	}

	public static func saveEvent(_ event: SmokingEvent) async throws {
	}

	public static func fetchEvents() async throws -> [SmokingEvent] {
		return []
	}
}


