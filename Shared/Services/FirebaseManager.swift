import Foundation

/// Placeholder Firebase manager to stub future cloud sync.
public enum FirebaseManager {
	public static func signInAnonymously() async throws {
		// TODO: Integrate FirebaseAuth in a future phase.
	}

	public static func saveEvent(_ event: SmokingEvent) async throws {
		// TODO: Save to Firestore in a future phase.
	}

	public static func fetchEvents() async throws -> [SmokingEvent] {
		// TODO: Fetch from Firestore in a future phase.
		return []
	}
}


